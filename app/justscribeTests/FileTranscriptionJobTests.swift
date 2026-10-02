//
//  FileTranscriptionJobTests.swift
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

/// Audio that is `seconds` long, handed out in one-second buffers of a steady tone. `duration`
/// is what the file claims, which for some files is missing (0) or only approximately right.
/// With `failAfter`, reading throws once that many buffers have been handed out.
private final class FakeSource: FileAudioSource, @unchecked Sendable {
    let duration: Double
    private var remaining: Int
    private var failAfter: Int?
    init(seconds: Int, duration: Double? = nil, failAfter: Int? = nil) {
        self.duration = duration ?? Double(seconds)
        remaining = seconds
        self.failAfter = failAfter
    }
    func next() async throws -> [Float]? {
        if let failAfter {
            guard failAfter > 0 else { throw AudioFileError.notReadable }
            self.failAfter = failAfter - 1
        }
        guard remaining > 0 else { return nil }
        remaining -= 1
        return (0..<16_000).map { $0 % 2 == 0 ? 0.5 : -0.5 }
    }
}

/// A file that cannot be read: it runs `beforeThrowing` on the main actor, then throws.
private final class UnreadableSource: FileAudioSource, @unchecked Sendable {
    let duration = 7.0
    private let beforeThrowing: @MainActor @Sendable () -> Void
    init(beforeThrowing: @escaping @MainActor @Sendable () -> Void) {
        self.beforeThrowing = beforeThrowing
    }
    func next() async throws -> [Float]? {
        await beforeThrowing()
        throw AudioFileError.notReadable
    }
}

/// Lets a source or an opener reach the job it was made for.
@MainActor
private final class JobBox {
    var job: FileTranscriptionJob?
    func cancel() { job?.cancel() }
}

@MainActor
private final class FakeTranscriber: TimedTranscribing {
    var isModelLoaded = true
    var modelGeneration = 1
    var calls = 0
    var failOnCall: Int?
    var changeModelOnCall: Int?
    var unloadOnCall: Int?
    var wordsPerChunk: [[TimedWord]] = []
    var onCall: (() -> Void)?

    struct Boom: LocalizedError { var errorDescription: String? { "the model fell over" } }

    func transcribeTimed(_ buffer: [Float], language: String?) async throws -> [TimedWord] {
        calls += 1
        onCall?()
        if failOnCall == calls { throw Boom() }
        if changeModelOnCall == calls { modelGeneration += 1 }
        if unloadOnCall == calls {
            // As the real service does when the model is unloaded while a chunk waits its turn.
            isModelLoaded = false
            throw Boom()
        }
        if calls <= wordsPerChunk.count { return wordsPerChunk[calls - 1] }
        return [TimedWord(text: " chunk\(calls).", start: 1, end: 2)]
    }
}

@MainActor
private final class FakeDictation: DictationActivity {
    /// When set, dictation reads as over from this moment, even if nothing else gets to run.
    var endsAt: ContinuousClock.Instant?
    private var dictating = false
    var isDictating: Bool {
        get { dictating && (endsAt.map { ContinuousClock.now < $0 } ?? true) }
        set { dictating = newValue }
    }
}

@MainActor
private final class FakeSpeakers: SpeakerTurnProviding {
    var result: Result<[SpeakerTurn], Error> = .success([])
    var requested: Int??
    var onTurns: (() -> Void)?
    /// When set, the pass waits until it is cancelled, as one queued behind another pass does.
    var waitsForCancel = false
    struct Boom: Error {}
    func turns(for url: URL, speakerCount: Int?) async throws -> [SpeakerTurn] {
        requested = .some(speakerCount)
        onTurns?()
        if waitsForCancel { try await Task.sleep(for: .seconds(30)) }
        return try result.get()
    }
}

@MainActor
struct FileTranscriptionJobTests {
    private let url = URL(fileURLWithPath: "/tmp/interview.m4a")

    private func makeJob(
        seconds: Int, speakers: SpeakerRequest = .none,
        transcriber: FakeTranscriber? = nil, dictation: FakeDictation? = nil,
        provider: FakeSpeakers? = nil, open: (@Sendable (URL) async throws -> any FileAudioSource)? = nil
    ) -> FileTranscriptionJob {
        // Default arguments are evaluated outside the main actor, so the fakes are made here.
        FileTranscriptionJob(
            url: url, language: "en", speakers: speakers,
            transcriber: transcriber ?? FakeTranscriber(), dictation: dictation ?? FakeDictation(),
            speakerProvider: provider ?? FakeSpeakers(),
            openSource: open ?? { _ in FakeSource(seconds: seconds) },
            pollInterval: .milliseconds(5))
    }

    /// Polls until `condition` holds or two seconds pass; false on timeout.
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() {
            if ContinuousClock.now > deadline { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    @Test func aShortFileIsOneChunkAndFinishes() async {
        let transcriber = FakeTranscriber()
        let job = makeJob(seconds: 7, transcriber: transcriber)
        await job.run()
        #expect(job.phase == .finished)
        #expect(transcriber.calls == 1)
        #expect(job.text == "[00:00:01]\nchunk1.")
    }

    @Test func timesAreShiftedByWhereTheChunkStarts() async {
        // 70 s of steady tone: the chunker cuts at 20.05 s and 40.10 s, then the rest.
        let transcriber = FakeTranscriber()
        let job = makeJob(seconds: 70, transcriber: transcriber)
        await job.run()
        #expect(transcriber.calls == 3)
        let starts = job.paragraphs.map(\.start)
        #expect(starts.count == 3)
        for (start, expected) in zip(starts, [1, 21.05, 41.1]) {
            #expect(abs(start - expected) < 0.000_001)
        }
        #expect(job.phase == .finished)
    }

    @Test func theSpeakerPassLabelsParagraphs() async {
        let provider = FakeSpeakers()
        provider.result = .success([
            SpeakerTurn(speaker: "A", start: 0, end: 20.05), SpeakerTurn(speaker: "B", start: 20.05, end: 70),
        ])
        // 45 s is two chunks: 0–20.05 s and the rest, so one word at 1 s and one at 21.05 s.
        let job = makeJob(seconds: 45, speakers: .exactly(2), provider: provider)
        await job.run()
        #expect(provider.requested == .some(2))
        #expect(job.paragraphs.map(\.speaker) == [1, 2])
        #expect(job.text.hasPrefix("[00:00:01] Speaker 1\nchunk1."))
    }

    @Test func detectingSpeakersPassesNoCount() async {
        let provider = FakeSpeakers()
        let job = makeJob(seconds: 5, speakers: .detect, provider: provider)
        await job.run()
        #expect(provider.requested == .some(nil))
    }

    @Test func aFailedSpeakerPassFailsBeforeTranscribing() async {
        let transcriber = FakeTranscriber()
        let provider = FakeSpeakers()
        provider.result = .failure(FakeSpeakers.Boom())
        let job = makeJob(seconds: 30, speakers: .detect, transcriber: transcriber, provider: provider)
        await job.run()
        #expect(job.phase == .failed(FileTranscriptionJob.Message.speakersFailed))
        #expect(transcriber.calls == 0)
    }

    @Test func noModelLoadedFailsAtOnce() async {
        let transcriber = FakeTranscriber()
        transcriber.isModelLoaded = false
        let job = makeJob(seconds: 30, transcriber: transcriber)
        await job.run()
        #expect(job.phase == .failed(FileTranscriptionJob.Message.noModel))
        #expect(transcriber.calls == 0)
    }

    @Test func anUnreadableFileReportsItsOwnSentence() async {
        let job = makeJob(seconds: 0, open: { _ in throw AudioFileError.noAudioTrack })
        await job.run()
        #expect(job.phase == .failed("This file has no audio"))
    }

    @Test func aFileWithNoSpeechSaysSo() async {
        let transcriber = FakeTranscriber()
        transcriber.wordsPerChunk = [[]]
        let job = makeJob(seconds: 5, transcriber: transcriber)
        await job.run()
        #expect(job.phase == .failed(FileTranscriptionJob.Message.noSpeech))
    }

    @Test func anEmptyFileSaysNoSpeechWithoutCallingTheModel() async {
        let transcriber = FakeTranscriber()
        let job = makeJob(seconds: 0, transcriber: transcriber)
        await job.run()
        #expect(job.phase == .failed(FileTranscriptionJob.Message.noSpeech))
        #expect(transcriber.calls == 0)
    }

    @Test func aFailingChunkStopsTheJobAndKeepsTheText() async {
        let transcriber = FakeTranscriber()
        transcriber.failOnCall = 2
        let job = makeJob(seconds: 70, transcriber: transcriber)
        await job.run()
        #expect(job.phase == .failed("Transcription stopped: the model fell over"))
        #expect(job.paragraphs.count == 1)
    }

    @Test func aChangedModelStopsTheJobAndKeepsTheText() async {
        let transcriber = FakeTranscriber()
        transcriber.changeModelOnCall = 1
        let job = makeJob(seconds: 70, transcriber: transcriber)
        await job.run()
        #expect(job.phase == .failed(FileTranscriptionJob.Message.modelChanged))
        #expect(transcriber.calls == 1)
        #expect(job.paragraphs.count == 1)
    }

    @Test func cancellingStopsAfterTheCurrentChunkAndKeepsTheText() async {
        let transcriber = FakeTranscriber()
        let job = makeJob(seconds: 70, transcriber: transcriber)
        transcriber.onCall = { if transcriber.calls == 1 { job.cancel() } }
        await job.run()
        #expect(job.phase == .cancelled)
        #expect(transcriber.calls == 1)
        #expect(job.paragraphs.count == 1)
    }

    @Test func itWaitsWhileDictationIsActiveAndResumesAfter() async {
        let transcriber = FakeTranscriber()
        let dictation = FakeDictation()
        dictation.isDictating = true
        let job = makeJob(seconds: 7, transcriber: transcriber, dictation: dictation)
        let running = Task { await job.run() }
        #expect(await waitUntil { job.phase == .pausedForDictation(0) })
        #expect(transcriber.calls == 0)
        dictation.isDictating = false
        await running.value
        #expect(transcriber.calls == 1)
        #expect(job.phase == .finished)
    }

    /// The claimed duration is exact (70), missing (0), too short (30) or too long (140).
    @Test(arguments: [70.0, 0, 30, 140])
    func progressNeverGoesBackwardsAndIsRunningFollowsThePhase(claimedDuration: Double) async {
        let transcriber = FakeTranscriber()
        let job = makeJob(
            seconds: 70, transcriber: transcriber,
            open: { _ in FakeSource(seconds: 70, duration: claimedDuration) })
        var seen: [Double] = []
        transcriber.onCall = {
            if case .transcribing(let fraction) = job.phase { seen.append(fraction) }
            #expect(job.isRunning)
        }
        #expect(!job.isRunning)
        #expect(!job.isDurationKnown)
        await job.run()
        #expect(job.isDurationKnown == (claimedDuration > 0))
        #expect(job.phase == .finished)
        #expect(seen.count == 3)
        #expect(seen == seen.sorted())
        #expect(seen.allSatisfy { $0 >= 0 && $0 <= 1 })
        #expect(!job.isRunning)
    }

    @Test func cancellingWhilePausedForDictationEndsWithoutTranscribing() async {
        let transcriber = FakeTranscriber()
        let dictation = FakeDictation()
        dictation.isDictating = true
        let job = makeJob(seconds: 7, transcriber: transcriber, dictation: dictation)
        let running = Task { await job.run() }
        #expect(await waitUntil { job.phase == .pausedForDictation(0) })
        job.cancel()
        await running.value
        #expect(job.phase == .cancelled)
        #expect(transcriber.calls == 0)
    }

    @Test func cancellingDuringTheSpeakerPassEndsBeforeAnyChunk() async {
        let transcriber = FakeTranscriber()
        let provider = FakeSpeakers()
        let job = makeJob(seconds: 30, speakers: .detect, transcriber: transcriber, provider: provider)
        provider.onTurns = { job.cancel() }
        await job.run()
        #expect(job.phase == .cancelled)
        #expect(transcriber.calls == 0)
    }

    @Test func cancellingWhileTheSpeakerPassWaitsItsTurnEndsAtOnce() async {
        let transcriber = FakeTranscriber()
        let provider = FakeSpeakers()
        provider.waitsForCancel = true
        let job = makeJob(seconds: 30, speakers: .detect, transcriber: transcriber, provider: provider)
        let running = Task { await job.run() }
        #expect(await waitUntil { provider.requested != nil })
        job.cancel()
        #expect(await waitUntil { job.phase == .cancelled })
        #expect(transcriber.calls == 0)
        // Ends a run that ignored the cancel, so a failure does not leave it waiting.
        running.cancel()
    }

    @Test func aSourceFailingPartWayKeepsTheEarlierText() async {
        // The first chunk is cut once 30 s are buffered; reading fails at 45 s, before a second.
        let transcriber = FakeTranscriber()
        let job = makeJob(
            seconds: 70, transcriber: transcriber,
            open: { _ in FakeSource(seconds: 70, failAfter: 45) })
        await job.run()
        #expect(job.phase == .failed(AudioFileError.notReadable.message))
        #expect(transcriber.calls == 1)
        #expect(job.paragraphs.count == 1)
    }

    @Test func aReadErrorDuringAPendingCancelEndsCancelled() async {
        let box = JobBox()
        let job = makeJob(seconds: 0, open: { _ in UnreadableSource { box.cancel() } })
        box.job = job
        await job.run()
        #expect(job.phase == .cancelled)
    }

    @Test func anOpenErrorDuringAPendingCancelEndsCancelled() async {
        let box = JobBox()
        let job = makeJob(seconds: 0, open: { _ in
            await box.cancel()
            throw AudioFileError.notReadable
        })
        box.job = job
        await job.run()
        #expect(job.phase == .cancelled)
    }

    @Test func theSpeakerPassWaitsForDictationToEnd() async {
        let transcriber = FakeTranscriber()
        let dictation = FakeDictation()
        dictation.isDictating = true
        let provider = FakeSpeakers()
        let job = makeJob(seconds: 7, speakers: .detect, transcriber: transcriber, dictation: dictation, provider: provider)
        let running = Task { await job.run() }
        #expect(await waitUntil { job.phase == .pausedForDictation(0) })
        #expect(provider.requested == nil)
        dictation.isDictating = false
        await running.value
        #expect(provider.requested == .some(nil))
        #expect(transcriber.calls == 1)
        #expect(job.phase == .finished)
    }

    @Test func cancellingWhileTheSpeakerPassWaitsForDictationSkipsThePass() async {
        let transcriber = FakeTranscriber()
        let dictation = FakeDictation()
        dictation.isDictating = true
        let provider = FakeSpeakers()
        let job = makeJob(seconds: 7, speakers: .detect, transcriber: transcriber, dictation: dictation, provider: provider)
        let running = Task { await job.run() }
        #expect(await waitUntil { job.phase == .pausedForDictation(0) })
        job.cancel()
        await running.value
        #expect(job.phase == .cancelled)
        #expect(provider.requested == nil)
        #expect(transcriber.calls == 0)
    }

    @Test func theModelUnloadedDuringAPauseSaysTheModelChanged() async {
        let transcriber = FakeTranscriber()
        let dictation = FakeDictation()
        dictation.isDictating = true
        let job = makeJob(seconds: 7, transcriber: transcriber, dictation: dictation)
        let running = Task { await job.run() }
        #expect(await waitUntil { job.phase == .pausedForDictation(0) })
        transcriber.isModelLoaded = false
        dictation.isDictating = false
        await running.value
        #expect(job.phase == .failed(FileTranscriptionJob.Message.modelChanged))
        #expect(transcriber.calls == 0)
    }

    @Test func theModelUnloadedUnderAChunkSaysTheModelChanged() async {
        let transcriber = FakeTranscriber()
        transcriber.unloadOnCall = 2
        let job = makeJob(seconds: 70, transcriber: transcriber)
        await job.run()
        #expect(job.phase == .failed(FileTranscriptionJob.Message.modelChanged))
        #expect(job.paragraphs.count == 1)
    }

    @Test func isCancellingLastsFromTheRequestToTheEnd() async {
        let transcriber = FakeTranscriber()
        let job = makeJob(seconds: 70, transcriber: transcriber)
        var duringRun: [Bool] = []
        transcriber.onCall = {
            duringRun.append(job.isCancelling)
            job.cancel()
            duringRun.append(job.isCancelling)
        }
        await job.run()
        #expect(duringRun == [false, true])
        #expect(job.phase == .cancelled)
        #expect(!job.isCancelling)
    }

    @Test func cancellingAJobThatIsNotRunningDoesNothing() async {
        let idle = makeJob(seconds: 7)
        idle.cancel()
        #expect(!idle.isCancelling)
        #expect(idle.phase == .idle)

        let finished = makeJob(seconds: 7)
        await finished.run()
        finished.cancel()
        #expect(!finished.isCancelling)
        #expect(finished.phase == .finished)
    }

    @Test func aCancelRightAfterStartIsNotLost() async {
        let transcriber = FakeTranscriber()
        let job = makeJob(seconds: 7, transcriber: transcriber)
        job.start()
        job.cancel()
        #expect(job.isCancelling)
        #expect(job.isRunning)
        #expect(await waitUntil { !job.isRunning })
        #expect(job.phase == .cancelled)
        #expect(transcriber.calls == 0)
        #expect(!job.isCancelling)
    }

    @Test func runningAFinishedJobAgainChangesNothing() async {
        let transcriber = FakeTranscriber()
        let job = makeJob(seconds: 7, transcriber: transcriber)
        await job.run()
        let paragraphs = job.paragraphs
        await job.run()
        #expect(transcriber.calls == 1)
        #expect(job.phase == .finished)
        #expect(job.paragraphs == paragraphs)
    }

    @Test func aCancelledTaskEndsTheJob() async {
        let transcriber = FakeTranscriber()
        let dictation = FakeDictation()
        dictation.isDictating = true
        let job = makeJob(seconds: 7, transcriber: transcriber, dictation: dictation)
        let running = Task { await job.run() }
        #expect(await waitUntil { job.phase == .pausedForDictation(0) })
        // Without an end to dictation a job that ignored the cancellation would wait forever;
        // with one, such a job goes on to transcribe and the expectations below fail instead.
        dictation.endsAt = .now + .milliseconds(300)
        running.cancel()
        await running.value
        #expect(job.phase == .cancelled)
        #expect(transcriber.calls == 0)
    }
}
