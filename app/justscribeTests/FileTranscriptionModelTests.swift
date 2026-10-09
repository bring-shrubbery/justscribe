//
//  FileTranscriptionModelTests.swift
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
private final class ShortSource: FileAudioSource, @unchecked Sendable {
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
        return [TimedWord(text: " hello.", start: 1, end: 2)]
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
    var turnsCalls = 0
    var turnsError: Error?
    struct Boom: Error {}

    func prepare() async throws {
        prepareCalls += 1
        if let prepareError { throw prepareError }
        isReady = true
    }

    func turns(for url: URL, speakerCount: Int?) async throws -> [SpeakerTurn] {
        turnsCalls += 1
        if let turnsError { throw turnsError }
        return []
    }
}

/// A class, so each test's throwaway defaults domain is removed when the test ends.
@MainActor
final class FileTranscriptionModelTests {
    private let url = URL(fileURLWithPath: "/tmp/interview.m4a")
    private let transcriber = FakeTranscriber()
    private let dictation = FakeDictation()
    private let speakers = FakeSpeakerModels()
    /// A throwaway domain: the test host shares the app's bundle ID and so its defaults.
    private let suiteName = "FileTranscriptionModelTests.\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// What the model asked to be saved to Transcripts: (text, title).
    private let saved = SavedBox()

    @MainActor
    private final class SavedBox {
        var items: [(String, String)] = []
        var error: Error?
        struct Boom: LocalizedError { var errorDescription: String? { "disk full" } }
    }

    private func makeModel() -> FileTranscriptionModel {
        FileTranscriptionModel(
            transcriber: transcriber, dictation: dictation, diarization: speakers, defaults: defaults,
            openSource: { _ in ShortSource() }, pollInterval: .milliseconds(5),
            saveTranscript: { [saved] text, title in
                if let error = saved.error { throw error }
                saved.items.append((text, title))
            })
    }

    @Test func aFinishedFileIsSavedToTranscriptsUnderItsName() async {
        let model = makeModel()
        model.open(url)
        #expect(await waitUntil { model.job?.phase == .finished })
        #expect(await waitUntil { !saved.items.isEmpty })
        #expect(saved.items.count == 1)
        #expect(saved.items.first?.1 == url.deletingPathExtension().lastPathComponent)
        #expect(saved.items.first?.0 == model.job?.text)
        #expect(model.notice == FileTranscriptionModel.Notice.saved)
    }

    @Test func aSaveThatFailsSaysSoAndKeepsTheTranscript() async {
        saved.error = SavedBox.Boom()
        let model = makeModel()
        model.open(url)
        #expect(await waitUntil { model.job?.phase == .finished })
        #expect(await waitUntil { model.notice != nil })
        #expect(model.notice == FileTranscriptionModel.Notice.saveFailed("disk full"))
        #expect(model.job?.paragraphs.isEmpty == false)
    }

    /// Polls until `condition` holds or ten seconds pass; false on timeout. Generous because a
    /// busy CI runner can take seconds to run a job that takes milliseconds here.
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition() {
            if ContinuousClock.now > deadline { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    // MARK: - Jobs

    @Test func openingWhileAJobRunsIsIgnored() async {
        dictation.isDictating = true
        let model = makeModel()
        model.open(url)
        let first = model.job
        #expect(await waitUntil { first?.phase == .pausedForDictation(0) })
        model.open(URL(fileURLWithPath: "/tmp/other.m4a"))
        #expect(model.job === first)
        dictation.isDictating = false
        #expect(await waitUntil { first?.phase == .finished })
    }

    @Test func resetWaitsForTheJobToEnd() async {
        dictation.isDictating = true
        let model = makeModel()
        model.open(url)
        let job = model.job
        #expect(await waitUntil { job?.phase == .pausedForDictation(0) })
        model.reset()
        #expect(model.job === job)
        dictation.isDictating = false
        #expect(await waitUntil { job?.phase == .finished })
        model.reset()
        #expect(model.job == nil)
    }

    @Test func discardDropsARunningJobAtOnceAndTheJobEndsCancelled() async {
        dictation.isDictating = true
        let model = makeModel()
        model.open(url)
        let job = model.job
        #expect(await waitUntil { job?.phase == .pausedForDictation(0) })
        model.discard()
        #expect(model.job == nil)
        #expect(await waitUntil { job?.phase == .cancelled })
        #expect(transcriber.calls == 0)
    }

    @Test func discardRightAfterOpenStillStopsTheJob() async {
        let model = makeModel()
        model.open(url)
        let job = model.job
        model.discard()
        #expect(model.job == nil)
        #expect(await waitUntil { job?.phase == .cancelled })
        #expect(transcriber.calls == 0)
    }

    @Test func retryingWithoutSpeakersRunsTheSameFileWithNoSpeakerPass() async {
        speakers.turnsError = FakeSpeakerModels.Boom()
        let model = makeModel()
        model.identifySpeakers = true
        model.open(url)
        let failed = model.job
        #expect(await waitUntil { failed?.phase == .failed(FileTranscriptionJob.Message.speakersFailed) })
        #expect(speakers.turnsCalls == 1)

        model.retryWithoutSpeakers()
        let retry = model.job
        #expect(retry !== failed)
        #expect(retry?.url == url)
        #expect(await waitUntil { retry?.phase == .finished })
        #expect(speakers.turnsCalls == 1)
        #expect(transcriber.calls == 1)
    }

    // MARK: - Speaker models

    @Test func aFailedDownloadSaysSoAndTurnsSpeakersOff() async {
        speakers.isReady = false
        speakers.prepareError = FakeSpeakerModels.Boom()
        let model = makeModel()
        model.identifySpeakers = true
        #expect(await waitUntil { model.notice != nil })
        #expect(model.notice == FileTranscriptionModel.Notice.speakerDownloadFailed)
        #expect(!model.identifySpeakers)
        #expect(!defaults.bool(forKey: FileTranscriptionModel.identifySpeakersKey))
    }

    @Test func speakersAlreadyOnFetchTheModelsWhenTheModelIsMade() async {
        defaults.set(true, forKey: FileTranscriptionModel.identifySpeakersKey)
        speakers.isReady = false
        let model = makeModel()
        #expect(model.identifySpeakers)
        #expect(await waitUntil { speakers.prepareCalls == 1 })
        model.prepareSpeakerModelsIfNeeded()
        try? await Task.sleep(for: .milliseconds(20))
        #expect(speakers.prepareCalls == 1)
    }

    @Test func readyOrSwitchedOffSpeakerModelsAreNotFetched() async {
        let model = makeModel()
        model.prepareSpeakerModelsIfNeeded()
        speakers.isReady = true
        model.identifySpeakers = true
        try? await Task.sleep(for: .milliseconds(20))
        #expect(speakers.prepareCalls == 0)
    }

    @Test func anUnreadableDropSaysSo() {
        let model = makeModel()
        model.refuseDrop()
        #expect(model.notice == FileTranscriptionModel.Notice.unreadableDrop)
    }

    @Test func theCountHintFlagsACountThatWillBeIgnored() {
        for text in ["", "  ", "2", " 10 "] {
            #expect(FileTranscriptionModel.speakerCountHint(for: text) == FileTranscriptionModel.SpeakerCountHint.normal)
        }
        for text in ["0", "11", "-2", "two", "2.5"] {
            #expect(FileTranscriptionModel.speakerCountHint(for: text) == FileTranscriptionModel.SpeakerCountHint.invalid)
        }
    }

    @Test func theCountHintSaysOneSpeakerGetsNoLabels() {
        for text in ["1", " 1 "] {
            #expect(FileTranscriptionModel.speakerCountHint(for: text) == FileTranscriptionModel.SpeakerCountHint.single)
        }
        #expect(FileTranscriptionModel.SpeakerCountHint.single == "One speaker — no labels are added")
    }

    // MARK: - Pure rules

    @Test func speakersOffMeansNoSpeakerPass() {
        #expect(FileTranscriptionModel.speakerRequest(identify: false, countText: "3") == .none)
    }

    @Test func anEmptyCountMeansDetect() {
        #expect(FileTranscriptionModel.speakerRequest(identify: true, countText: "") == .detect)
        #expect(FileTranscriptionModel.speakerRequest(identify: true, countText: "  ") == .detect)
    }

    @Test func aCountFromTwoToTenIsExact() {
        #expect(FileTranscriptionModel.speakerRequest(identify: true, countText: "2") == .exactly(2))
        #expect(FileTranscriptionModel.speakerRequest(identify: true, countText: " 10 ") == .exactly(10))
    }

    @Test func aCountOfOneMeansNoSpeakerPass() {
        #expect(FileTranscriptionModel.speakerRequest(identify: true, countText: "1") == .none)
        #expect(FileTranscriptionModel.speakerRequest(identify: true, countText: " 1 ") == .none)
    }

    @Test func anythingElseFallsBackToDetect() {
        for text in ["0", "11", "-2", "two", "2.5"] {
            #expect(FileTranscriptionModel.speakerRequest(identify: true, countText: text) == .detect)
        }
    }

    @Test func theSaveNameReplacesTheExtension() {
        #expect(FileTranscriptionModel.saveName(for: URL(fileURLWithPath: "/a/b/interview.final.m4a")) == "interview.final.txt")
        #expect(FileTranscriptionModel.saveName(for: URL(fileURLWithPath: "/a/recording")) == "recording.txt")
    }

    // MARK: - Status line

    private func status(
        _ phase: FileTranscriptionJob.Phase, cancelling: Bool = false, durationKnown: Bool = true
    ) -> FileTranscriptionModel.Status {
        FileTranscriptionModel.status(phase: phase, isCancelling: cancelling, isDurationKnown: durationKnown)
    }

    @Test func openingIsIndeterminate() {
        #expect(status(.idle, durationKnown: false) == .working("Opening…", progress: nil))
    }

    @Test func identifyingSpeakersIsIndeterminate() {
        #expect(status(.identifyingSpeakers) == .working("Identifying speakers…", progress: nil))
    }

    @Test func transcribingShowsAPercentageWhenTheDurationIsKnown() {
        #expect(status(.transcribing(0.427)) == .working("Transcribing… 42%", progress: 0.427))
    }

    @Test func transcribingIsIndeterminateWhenTheDurationIsUnknown() {
        #expect(status(.transcribing(0), durationKnown: false) == .working("Transcribing…", progress: nil))
    }

    @Test func pausedKeepsItsProgressOnlyWhenTheDurationIsKnown() {
        #expect(status(.pausedForDictation(0.5)) == .working("Paused while you dictate", progress: 0.5))
        #expect(status(.pausedForDictation(0), durationKnown: false) == .working("Paused while you dictate", progress: nil))
    }

    @Test func aPendingCancelSaysStoppingWhateverThePhase() {
        for phase: FileTranscriptionJob.Phase in [.idle, .identifyingSpeakers, .transcribing(0.3), .pausedForDictation(0.3)] {
            #expect(status(phase, cancelling: true) == .working("Stopping…", progress: nil))
        }
    }

    @Test func finalPhasesEnd() {
        #expect(status(.finished) == .ended("Done", systemImage: "checkmark.circle.fill"))
        #expect(status(.cancelled) == .ended("Cancelled", systemImage: "xmark.circle"))
        #expect(status(.failed(FileTranscriptionJob.Message.noSpeech))
            == .ended(FileTranscriptionJob.Message.noSpeech, systemImage: "exclamationmark.triangle.fill"))
    }
}
