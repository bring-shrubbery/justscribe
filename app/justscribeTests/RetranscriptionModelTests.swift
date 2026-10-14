//
//  RetranscriptionModelTests.swift
//  justscribeTests
//
//  Copyright (C) 2026 Quassum MB
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import Foundation
import Testing
@testable import justscribe

/// Seven seconds of steady tone: one chunk.
private final class ToneSource: FileAudioSource, @unchecked Sendable {
    let duration = 7.0
    private var remaining = 7
    func next() async throws -> [Float]? {
        guard remaining > 0 else { return nil }
        remaining -= 1
        return (0..<16_000).map { $0 % 2 == 0 ? 0.5 : -0.5 }
    }
}

@MainActor
private final class FakeTranscriber: TimedTranscribing {
    var isModelLoaded = true
    var modelGeneration = 1
    var calls = 0
    func transcribeTimed(_ buffer: [Float], language: String?) async throws -> [TimedWord] {
        calls += 1
        return [TimedWord(text: " again.", start: 1, end: 2)]
    }
}

@MainActor
private final class FakeDictation: DictationActivity {
    var isDictating = false
}

@MainActor
private final class FakeSpeakerModels: SpeakerModelProviding {
    var isReady = true
    var downloadProgress: Double?
    var prepareCalls = 0
    var prepareError: Error?
    struct Boom: LocalizedError { var errorDescription: String? { "boom" } }

    func prepare() async throws {
        prepareCalls += 1
        if let prepareError { throw prepareError }
        isReady = true
    }

    func turns(for url: URL, speakerCount: Int?) async throws -> [SpeakerTurn] { [] }
}

/// A class, so the temporary folder and defaults domain go when the test ends.
@MainActor
final class RetranscriptionModelTests {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("RetranscriptionModelTests-\(UUID().uuidString)", isDirectory: true)
    private let suiteName = "RetranscriptionModelTests.\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let store: TranscriptStore
    private let transcriber = FakeTranscriber()
    private let dictation = FakeDictation()
    private let speakers = FakeSpeakerModels()
    private let whisper = UnifiedModelInfo.model(forID: "whisperkit:openai_whisper-large-v3")!
    private let parakeet = UnifiedModelInfo.model(forID: "fluidaudio:v3")!

    /// What the model asked to be loaded, in order; "restore" for a load of the user's own.
    private var loads: [String] = []
    private var loadError: Error?
    struct LoadBoom: LocalizedError { var errorDescription: String? { "no memory" } }

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
        store = TranscriptStore(directory: directory, remove: { try FileManager.default.removeItem(at: $0) })
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeModel() -> RetranscriptionModel {
        RetranscriptionModel(
            store: store, transcriber: transcriber, dictation: dictation, diarization: speakers, defaults: defaults,
            availableModels: { [self.parakeet, self.whisper] },
            loadedModelID: { "fluidaudio:v3" },
            loadModel: { [unowned self] id in
                self.loads.append(id)
                if let error = self.loadError { throw error }
            },
            restoreModel: { [unowned self] in self.loads.append("restore") },
            openSource: { _ in ToneSource() }, pollInterval: .milliseconds(5))
    }

    /// A transcript with a recording next to it, as a long dictation leaves one.
    private func savedWithAudio() throws -> SavedTranscript {
        let audio = directory.appendingPathComponent("recording.m4a")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not really audio".utf8).write(to: audio)
        let saved = try store.save("first try", title: "Long Dictation", date: Date(timeIntervalSince1970: 1_000_000), audio: audio)
        #expect(saved.audioURL != nil)
        return saved
    }

    @Test func aRunSavesANewTranscriptNextToTheOriginalSharingItsRecording() async throws {
        let original = try savedWithAudio()
        let model = makeModel()
        model.start(original, model: whisper, speakers: .none)
        #expect(model.isRunning)
        #expect(await waitUntil { !model.isRunning })

        #expect(store.transcripts.count == 2)
        let copy = try #require(store.transcripts.first { $0.url != original.url })
        #expect(copy.title == "Long Dictation (Whisper Large v3)")
        #expect(copy.date == original.date)
        #expect(copy.audioURL != nil)
        #expect(try store.text(of: copy).contains("again."))
        // The original keeps its text and recording.
        #expect(try store.text(of: original) == "first try")
        #expect(FileManager.default.fileExists(atPath: original.audioURL!.path))
        #expect(store.requestedSelection == copy.url)
        #expect(loads == ["whisperkit:openai_whisper-large-v3", "restore"])
        #expect(model.notice == nil)
    }

    @Test func aModelThatDoesNotLoadSaysSoAndLoadsTheUsersBack() async throws {
        let original = try savedWithAudio()
        loadError = LoadBoom()
        let model = makeModel()
        model.start(original, model: whisper, speakers: .none)
        #expect(await waitUntil { !model.isRunning })
        #expect(model.notice == RetranscriptionModel.Notice.modelFailed("no memory"))
        #expect(model.noticeURL == original.url)
        #expect(store.transcripts.count == 1)
        #expect(loads == ["whisperkit:openai_whisper-large-v3", "restore"])
        #expect(transcriber.calls == 0)
    }

    @Test func aCancelWhileDictationHoldsTheJobSavesNothing() async throws {
        let original = try savedWithAudio()
        dictation.isDictating = true
        let model = makeModel()
        model.start(original, model: whisper, speakers: .none)
        #expect(await waitUntil { model.job?.phase == .pausedForDictation(0) })
        model.cancel()
        #expect(await waitUntil { !model.isRunning })
        #expect(store.transcripts.count == 1)
        #expect(model.notice == nil)
        #expect(transcriber.calls == 0)
        #expect(loads.last == "restore")
    }

    @Test func speakersOnFetchTheSpeakerModelFirstAndAFailedFetchEndsTheRun() async throws {
        let original = try savedWithAudio()
        speakers.isReady = false
        speakers.prepareError = FakeSpeakerModels.Boom()
        let model = makeModel()
        model.start(original, model: parakeet, speakers: .detect)
        #expect(await waitUntil { !model.isRunning })
        #expect(speakers.prepareCalls == 1)
        #expect(model.notice == RetranscriptionModel.Notice.speakerDownloadFailed)
        #expect(loads.isEmpty)
        #expect(store.transcripts.count == 1)
    }

    @Test func aTranscriptWithoutARecordingAndASecondStartAreIgnored() async throws {
        let plain = try store.save("text only", title: "Notes")
        let model = makeModel()
        model.start(plain, model: whisper, speakers: .none)
        #expect(!model.isRunning)

        let original = try savedWithAudio()
        dictation.isDictating = true
        model.start(original, model: whisper, speakers: .none)
        #expect(await waitUntil { model.job != nil })
        let job = model.job
        model.start(original, model: parakeet, speakers: .none)
        #expect(model.job === job)
        #expect(loads == ["whisperkit:openai_whisper-large-v3"])
        model.cancel()
        #expect(await waitUntil { !model.isRunning })
    }

    @Test func theTitleNamesTheModelOnceEvenForARetranscriptionOfARetranscription() {
        #expect(RetranscriptionModel.title(for: "Long Dictation", model: whisper) == "Long Dictation (Whisper Large v3)")
        #expect(RetranscriptionModel.title(for: "Long Dictation (Whisper Large v3)", model: parakeet) == "Long Dictation (Parakeet v3)")
        #expect(RetranscriptionModel.title(for: "Call (Parakeet v3) ", model: whisper) == "Call (Whisper Large v3)")
        // A parenthesis that is not a model name stays.
        #expect(RetranscriptionModel.title(for: "Standup (Monday)", model: whisper) == "Standup (Monday) (Whisper Large v3)")
    }

    /// Polls until `condition` holds or ten seconds pass; false on timeout.
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition() {
            if ContinuousClock.now > deadline { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }
}
