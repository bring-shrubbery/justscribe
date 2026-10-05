//
//  LiveTranscriptionSessionTests.swift
//  justscribeTests
//
//  Created by Antoni Silvestrovic on 24/01/2026.
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

/// A source the test feeds by hand.
private final class FakeSource: LiveAudioSource, @unchecked Sendable {
    let kind: LiveAudioKind
    let sink: LiveAudioSink
    var startError: Error?
    private(set) var isRunning = false
    private(set) var stopCalls = 0
    init(kind: LiveAudioKind, sink: @escaping LiveAudioSink) {
        self.kind = kind
        self.sink = sink
    }
    func start() throws {
        if let startError { throw startError }
        isRunning = true
    }
    func stop() {
        isRunning = false
        stopCalls += 1
    }
    /// `seconds` of a tone, or of silence.
    func feed(seconds: Double, silent: Bool = false) {
        let count = Int(seconds * Double(AudioChunker.sampleRate))
        sink(silent ? [Float](repeating: 0, count: count) : (0..<count).map { $0 % 2 == 0 ? 0.5 : -0.5 })
    }
}

@MainActor
private final class Sources {
    var made: [FakeSource] = []
    var failing: Set<LiveAudioKind> = []
    func make(_ kind: LiveAudioKind, sink: @escaping LiveAudioSink) throws -> any LiveAudioSource {
        let source = FakeSource(kind: kind, sink: sink)
        if failing.contains(kind) { source.startError = LiveAudioError.systemAudioUnavailable("test") }
        made.append(source)
        return source
    }
    subscript(kind: LiveAudioKind) -> FakeSource? { made.first { $0.kind == kind } }
}

@MainActor
private final class FakeTranscriber: TimedTranscribing {
    var isModelLoaded = true
    var modelGeneration = 1
    private(set) var calls: [[Float]] = []
    /// What each call returns, by order; after that, one word naming the call.
    var wordsPerCall: [[TimedWord]] = []
    var failOnCall: Int?
    struct Boom: LocalizedError { var errorDescription: String? { "the model fell over" } }
    func transcribeTimed(_ buffer: [Float], language: String?) async throws -> [TimedWord] {
        calls.append(buffer)
        if failOnCall == calls.count { throw Boom() }
        if calls.count <= wordsPerCall.count { return wordsPerCall[calls.count - 1] }
        return [TimedWord(text: " call\(calls.count).", start: 0.5, end: 1)]
    }
}

@MainActor
private final class FakeDictation: DictationActivity {
    var isDictating = false
}

@MainActor
private final class FakeSpeakers: SpeakerTurnProviding {
    var result: Result<[SpeakerTurn], Error> = .success([])
    var requested: Int??
    var fileExisted = false
    struct Boom: Error {}
    func turns(for url: URL, speakerCount: Int?) async throws -> [SpeakerTurn] {
        requested = .some(speakerCount)
        fileExisted = FileManager.default.fileExists(atPath: url.path)
        return try result.get()
    }
}

@MainActor
struct LiveTranscriptionSessionTests {
    private let transcriber = FakeTranscriber()
    private let dictation = FakeDictation()
    private let speakers = FakeSpeakers()
    private let sources = Sources()
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("LiveTranscriptionSessionTests-\(UUID().uuidString)", isDirectory: true)

    private func session(
        kinds: Set<LiveAudioKind> = [.microphone], speakers request: SpeakerRequest = .none
    ) -> LiveTranscriptionSession {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return LiveTranscriptionSession(
            kinds: kinds, language: nil, speakers: request,
            transcriber: transcriber, dictation: dictation, speakerProvider: speakers,
            makeSource: { kind, sink in try sources.make(kind, sink: sink) },
            isDictionaryWord: { _ in true },
            chunkSeconds: (10, 15), audioDirectory: directory, pollInterval: .milliseconds(5))
    }

    /// Lets the main queue hop and the worker run until `condition` holds, or ten seconds pass.
    private func wait(until condition: @escaping @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func audioIsTranscribedInChunksAsItArrivesAndTheRestOnStop() async throws {
        let session = session()
        try session.start()
        #expect(session.phase == .recording)
        let mic = try #require(sources[.microphone])
        mic.feed(seconds: 16)
        await wait { self.transcriber.calls.count == 1 }
        #expect(transcriber.calls.count == 1)
        #expect(transcriber.calls[0].count >= 10 * AudioChunker.sampleRate)
        #expect(transcriber.calls[0].count <= 15 * AudioChunker.sampleRate)
        await wait { !session.paragraphs.isEmpty }
        #expect(session.paragraphs.map(\.text) == ["call1."])
        #expect(session.paragraphs.first?.label == nil)
        #expect(session.elapsed == 16)

        session.stop()
        #expect(mic.stopCalls == 1)
        // Audio already on its way to the main queue when Stop is pressed is still taken in.
        mic.feed(seconds: 1)
        await wait { session.phase == .finished }
        #expect(session.phase == .finished)
        #expect(transcriber.calls.count == 2)
        #expect(transcriber.calls[1].count == 17 * AudioChunker.sampleRate - transcriber.calls[0].count)
        #expect(session.paragraphs.map(\.text) == ["call1.", "call2."])
        // The second chunk's word is placed after the first chunk, not at its own 0.5 s.
        #expect(session.paragraphs[1].start > 10)
        #expect(!session.isRunning)
    }

    @Test func withTwoSourcesTheMicrophoneIsYouAndTheRestOthers() async throws {
        let session = session(kinds: [.microphone, .systemAudio])
        try session.start()
        transcriber.wordsPerCall = [
            [TimedWord(text: " Hello", start: 0.2, end: 0.6)],
            [TimedWord(text: " Hi", start: 2.0, end: 2.4)],
        ]
        let mic = try #require(sources[.microphone])
        let system = try #require(sources[.systemAudio])
        mic.feed(seconds: 3)
        system.feed(seconds: 3)
        session.stop()
        await wait { session.phase == .finished }
        #expect(session.paragraphs.map(\.label) == ["You", "Others"])
        #expect(session.paragraphs.map(\.text) == ["Hello", "Hi"])
        #expect(session.text.hasPrefix("[00:00:00] You\nHello"))
    }

    @Test func silentAudioNeverReachesTheModel() async throws {
        let session = session(kinds: [.systemAudio])
        try session.start()
        let system = try #require(sources[.systemAudio])
        system.feed(seconds: 16, silent: true)
        session.stop()
        await wait { session.phase == .finished }
        #expect(transcriber.calls.isEmpty)
        #expect(session.paragraphs.isEmpty)
        #expect(LiveTranscriptionModel.status(of: session) == .ended(LiveTranscriptionSession.Message.noSpeech, systemImage: "waveform.slash"))
    }

    @Test func aChunkWaitsWhileDictationRuns() async throws {
        let session = session()
        try session.start()
        dictation.isDictating = true
        sources[.microphone]?.feed(seconds: 16)
        try await Task.sleep(for: .milliseconds(50))
        #expect(transcriber.calls.isEmpty)
        #expect(session.backlog == 1)
        dictation.isDictating = false
        await wait { self.transcriber.calls.count == 1 }
        #expect(transcriber.calls.count == 1)
        #expect(session.backlog == 0)
        session.cancel()
    }

    @Test func theSpeakerPassRunsOverTheSystemAudioAndRelabelsIt() async throws {
        let session = session(kinds: [.microphone, .systemAudio], speakers: .exactly(2))
        #expect(session.diarizedKind == .systemAudio)
        try session.start()
        transcriber.wordsPerCall = [
            [TimedWord(text: " Mine", start: 0.2, end: 0.6)],
            [TimedWord(text: " Alice", start: 0.5, end: 1.0), TimedWord(text: " Bob", start: 2.5, end: 3.0)],
        ]
        speakers.result = .success([SpeakerTurn(speaker: "s0", start: 0, end: 2), SpeakerTurn(speaker: "s1", start: 2, end: 4)])
        sources[.microphone]?.feed(seconds: 4)
        sources[.systemAudio]?.feed(seconds: 4)
        session.stop()
        await wait { session.phase == .finished }
        #expect(speakers.requested == .some(2))
        #expect(speakers.fileExisted)
        #expect(session.paragraphs.map(\.label) == ["You", "Speaker 1", "Speaker 2"])
        #expect(session.paragraphs.map(\.text) == ["Mine", "Alice", "Bob"])
        #expect(session.notice == nil)
        // The temporary audio is gone once the pass has read it.
        await wait { (try? FileManager.default.contentsOfDirectory(atPath: self.directory.path))?.isEmpty == true }
        #expect((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) == [])
    }

    @Test func aFailedSpeakerPassKeepsTheLiveLabels() async throws {
        let session = session(kinds: [.microphone, .systemAudio], speakers: .detect)
        try session.start()
        speakers.result = .failure(FakeSpeakers.Boom())
        sources[.microphone]?.feed(seconds: 2)
        sources[.systemAudio]?.feed(seconds: 2)
        session.stop()
        await wait { session.phase == .finished }
        #expect(speakers.requested == .some(nil))
        #expect(session.notice == LiveTranscriptionSession.Message.speakersFailed)
        #expect(session.paragraphs.map(\.label) == ["You", "Others"])
    }

    @Test func aSingleSourceWithSpeakersIsDiarizedItself() async throws {
        let session = session(kinds: [.microphone], speakers: .detect)
        #expect(session.diarizedKind == .microphone)
        try session.start()
        transcriber.wordsPerCall = [[TimedWord(text: " A", start: 0.5, end: 1), TimedWord(text: " B", start: 2.5, end: 3)]]
        speakers.result = .success([SpeakerTurn(speaker: "x", start: 0, end: 2), SpeakerTurn(speaker: "y", start: 2, end: 4)])
        sources[.microphone]?.feed(seconds: 4)
        session.stop()
        await wait { session.phase == .finished }
        #expect(session.paragraphs.map(\.label) == ["Speaker 1", "Speaker 2"])
    }

    @Test func aSourceThatCannotStartLeavesNothingRunning() async throws {
        sources.failing = [.systemAudio]
        let session = session(kinds: [.microphone, .systemAudio])
        #expect(throws: LiveAudioError.systemAudioUnavailable("test")) { try session.start() }
        #expect(session.phase == .idle)
        #expect(sources[.microphone]?.isRunning == false)
    }

    @Test func aModelFailureEndsTheSessionWithTheTextSoFar() async throws {
        let session = session()
        try session.start()
        transcriber.failOnCall = 2
        sources[.microphone]?.feed(seconds: 16)
        await wait { session.paragraphs.count == 1 }
        sources[.microphone]?.feed(seconds: 16)
        await wait { !session.isRunning }
        #expect(session.phase == .failed(LiveTranscriptionSession.Message.stopped("the model fell over")))
        #expect(session.paragraphs.map(\.text) == ["call1."])
        #expect(sources[.microphone]?.stopCalls == 1)
    }

    @Test func aModelChangeEndsTheSession() async throws {
        let session = session()
        try session.start()
        transcriber.modelGeneration += 1
        sources[.microphone]?.feed(seconds: 16)
        await wait { !session.isRunning }
        #expect(session.phase == .failed(LiveTranscriptionSession.Message.modelChanged))
    }

    @Test func withoutAModelTheSessionFailsAtOnce() throws {
        transcriber.isModelLoaded = false
        let session = session()
        try session.start()
        #expect(session.phase == .failed(LiveTranscriptionSession.Message.noModel))
        #expect(sources.made.isEmpty)
    }

    @Test func cancelStopsEverythingAndKeepsTheText() async throws {
        let session = session(kinds: [.microphone], speakers: .detect)
        try session.start()
        sources[.microphone]?.feed(seconds: 16)
        await wait { session.paragraphs.count == 1 }
        session.cancel()
        #expect(session.phase == .cancelled)
        #expect(sources[.microphone]?.stopCalls == 1)
        #expect(session.paragraphs.count == 1)
        // Audio fed after a cancel is ignored.
        sources[.microphone]?.feed(seconds: 16)
        try await Task.sleep(for: .milliseconds(30))
        #expect(transcriber.calls.count == 1)
        await wait { (try? FileManager.default.contentsOfDirectory(atPath: self.directory.path))?.isEmpty == true }
        #expect((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) == [])
    }

    @Test func statusLinesFollowThePhase() {
        typealias Status = LiveTranscriptionModel.Status
        #expect(LiveTranscriptionModel.status(phase: .recording, backlog: 0, hasText: false) == .recording)
        #expect(LiveTranscriptionModel.status(phase: .finishing, backlog: 1, hasText: true) == .working("Transcribing the last of the audio…"))
        #expect(LiveTranscriptionModel.status(phase: .finishing, backlog: 3, hasText: true) == .working("Transcribing the last 3 pieces…"))
        #expect(LiveTranscriptionModel.status(phase: .identifyingSpeakers, backlog: 0, hasText: true) == .working("Identifying speakers…"))
        #expect(LiveTranscriptionModel.status(phase: .finished, backlog: 0, hasText: true) == .ended("Done", systemImage: "checkmark.circle.fill"))
        #expect(LiveTranscriptionModel.status(phase: .cancelled, backlog: 0, hasText: true) == .ended("Stopped", systemImage: "xmark.circle"))
        #expect(LiveTranscriptionModel.status(phase: .failed("x"), backlog: 0, hasText: true) == .ended("x", systemImage: "exclamationmark.triangle.fill"))
    }

    @Test func captionsAndSaveName() {
        #expect(LiveTranscriptionModel.speakerCaption(kinds: [.microphone, .systemAudio]).hasPrefix("You are labelled from the microphone."))
        #expect(LiveTranscriptionModel.speakerCaption(kinds: [.microphone]).hasPrefix("Labels who said what"))
        #expect(LiveTranscriptionModel.speakerCountHint(for: "", kinds: [.microphone, .systemAudio]).hasPrefix("Not counting you."))
        #expect(LiveTranscriptionModel.speakerCountHint(for: "1", kinds: [.microphone, .systemAudio]) == FileTranscriptionModel.SpeakerCountHint.single)
        #expect(LiveTranscriptionModel.speakerCountHint(for: "", kinds: [.microphone]) == FileTranscriptionModel.SpeakerCountHint.normal)
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: .current, year: 2026, month: 10, day: 5, hour: 14, minute: 32))!
        #expect(LiveTranscriptionModel.saveName(for: date) == "Live Transcription 2026-10-05 at 14.32.txt")
    }
}
