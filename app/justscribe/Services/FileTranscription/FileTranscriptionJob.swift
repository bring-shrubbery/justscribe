//
//  FileTranscriptionJob.swift
//  justscribe
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
import Observation

/// Whether a dictation session is under way; file transcription waits while one is.
protocol DictationActivity: AnyObject {
    var isDictating: Bool { get }
}

/// Who spoke when in a file.
protocol SpeakerTurnProviding: AnyObject {
    func turns(for url: URL, speakerCount: Int?) async throws -> [SpeakerTurn]
}

/// What the user asked for about speakers.
nonisolated enum SpeakerRequest: Equatable, Sendable {
    case none
    case detect
    case exactly(Int)
}

/// One file's transcription, from the first sample to the last paragraph. It transcribes a
/// chunk at a time and, before each chunk, waits while dictation is active: dictation is
/// the app's first job and must never queue behind a long file.
@Observable
final class FileTranscriptionJob {
    enum Phase: Equatable {
        case idle
        case identifyingSpeakers
        /// The fraction of the file's duration transcribed so far.
        case transcribing(Double)
        case pausedForDictation(Double)
        case finished
        case cancelled
        case failed(String)
    }

    enum Message {
        static let noModel = "Choose a transcription model in Settings first"
        static let speakersFailed = "Couldn't identify speakers in this file"
        static let modelChanged = "The transcription model changed"
        static let noSpeech = "No speech was found in this file"
        static func stopped(_ reason: String) -> String { "Transcription stopped: \(reason)" }
    }

    private(set) var phase: Phase = .idle {
        didSet { if isFinal { isCancelling = false } }
    }
    private(set) var paragraphs: [TranscriptParagraph] = []
    /// Whether a cancel was asked for and the job is finishing the chunk in flight.
    private(set) var isCancelling = false
    /// Whether the file reported its duration; when it did not, progress stays at 0.
    private(set) var isDurationKnown = false
    var text: String { TranscriptBuilder.text(paragraphs) }

    /// From `start()` (or `run()`, called directly) until a final phase.
    var isRunning: Bool { (hasStarted || task != nil) && !isFinal }

    private var isFinal: Bool {
        switch phase {
        case .finished, .cancelled, .failed: true
        case .idle, .identifyingSpeakers, .transcribing, .pausedForDictation: false
        }
    }

    /// A cancel from the user or of the task running the job.
    private var shouldStop: Bool { isCancelling || Task.isCancelled }

    let url: URL
    private let language: String?
    private let speakers: SpeakerRequest
    private let transcriber: any TimedTranscribing
    private let dictation: any DictationActivity
    private let speakerProvider: any SpeakerTurnProviding
    private let openSource: @Sendable (URL) async throws -> any FileAudioSource
    private let pollInterval: Duration
    private var hasStarted = false
    private var task: Task<Void, Never>?

    init(
        url: URL, language: String?, speakers: SpeakerRequest,
        transcriber: any TimedTranscribing, dictation: any DictationActivity,
        speakerProvider: any SpeakerTurnProviding,
        openSource: @escaping @Sendable (URL) async throws -> any FileAudioSource = { try await AudioFileDecoder.open($0) },
        pollInterval: Duration = .milliseconds(200)
    ) {
        self.url = url
        self.language = language
        self.speakers = speakers
        self.transcriber = transcriber
        self.dictation = dictation
        self.speakerProvider = speakerProvider
        self.openSource = openSource
        self.pollInterval = pollInterval
    }

    func start() {
        guard task == nil else { return }
        task = Task { await run() }
    }

    /// Stops after the chunk in flight; the text so far stays. Does nothing unless running.
    /// A cancel between `start()` and the task's first turn ends the run before it opens the file.
    func cancel() {
        guard isRunning else { return }
        isCancelling = true
    }

    func run() async {
        guard phase == .idle, !hasStarted else { return }
        hasStarted = true
        if shouldStop {
            phase = .cancelled
            return
        }
        guard transcriber.isModelLoaded else {
            phase = .failed(Message.noModel)
            return
        }
        let generation = transcriber.modelGeneration
        var modelChanged: Bool { !transcriber.isModelLoaded || transcriber.modelGeneration != generation }

        // A local, so the file is closed whenever `run()` returns.
        let source: any FileAudioSource
        do {
            source = try await openSource(url)
        } catch let error as AudioFileError {
            phase = .failed(error.message)
            return
        } catch {
            phase = shouldStop ? .cancelled : .failed(AudioFileError.notReadable.message)
            return
        }
        let duration = source.duration
        isDurationKnown = duration > 0
        if shouldStop {
            phase = .cancelled
            return
        }

        var turns: [SpeakerTurn] = []
        if speakers != .none {
            phase = .identifyingSpeakers
            do {
                let count: Int? = if case .exactly(let number) = speakers { number } else { nil }
                turns = try await speakerProvider.turns(for: url, speakerCount: count)
            } catch {
                phase = shouldStop ? .cancelled : .failed(Message.speakersFailed)
                return
            }
            if shouldStop {
                phase = .cancelled
                return
            }
        }

        var words: [TimedWord] = []
        var chunker = AudioChunker()
        var fraction = 0.0
        phase = .transcribing(0)

        /// Transcribes one chunk; false when the job has ended (its phase says why).
        func transcribe(_ chunk: AudioChunk) async -> Bool {
            while dictation.isDictating, !shouldStop {
                phase = .pausedForDictation(fraction)
                try? await Task.sleep(for: pollInterval)
            }
            if shouldStop {
                phase = .cancelled
                return false
            }
            guard !modelChanged else {
                phase = .failed(Message.modelChanged)
                return false
            }
            phase = .transcribing(fraction)
            do {
                let chunkWords = try await transcriber.transcribeTimed(chunk.samples, language: language)
                words += chunkWords.map {
                    TimedWord(text: $0.text, start: $0.start + chunk.startSeconds, end: $0.end + chunk.startSeconds)
                }
            } catch {
                // An unload while the chunk queued for the model throws; say what happened.
                phase = modelChanged ? .failed(Message.modelChanged)
                    : shouldStop ? .cancelled
                    : .failed(Message.stopped(error.localizedDescription))
                return false
            }
            // Off the main actor: with many speaker turns a rebuild takes long enough to delay a hotkey.
            // Nothing else touches `words` or `paragraphs` meanwhile, as `run()` is entered once.
            paragraphs = await Self.buildParagraphs(words: words, turns: turns)
            let end = chunk.startSeconds + Double(chunk.samples.count) / Double(AudioChunker.sampleRate)
            fraction = duration > 0 ? min(1, max(fraction, end / duration)) : fraction
            // Checked after the rebuild, so a change or cancel made during it is seen.
            if modelChanged {
                phase = .failed(Message.modelChanged)
                return false
            }
            if shouldStop {
                phase = .cancelled
                return false
            }
            phase = .transcribing(fraction)
            return true
        }

        do {
            while let samples = try await source.next() {
                for chunk in chunker.append(samples) {
                    guard await transcribe(chunk) else { return }
                }
            }
        } catch let error as AudioFileError {
            phase = .failed(error.message)
            return
        } catch {
            phase = shouldStop ? .cancelled : .failed(AudioFileError.notReadable.message)
            return
        }
        if let last = chunker.finish() {
            guard await transcribe(last) else { return }
        }
        phase = paragraphs.isEmpty ? .failed(Message.noSpeech) : .finished
    }

    @concurrent
    private static func buildParagraphs(words: [TimedWord], turns: [SpeakerTurn]) async -> [TranscriptParagraph] {
        TranscriptBuilder.paragraphs(words: words, turns: turns)
    }
}
