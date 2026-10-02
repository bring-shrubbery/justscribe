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

    private(set) var phase: Phase = .idle
    private(set) var paragraphs: [TranscriptParagraph] = []
    var text: String { TranscriptBuilder.text(paragraphs) }

    var isRunning: Bool {
        switch phase {
        case .identifyingSpeakers, .transcribing, .pausedForDictation: true
        case .idle, .finished, .cancelled, .failed: false
        }
    }

    let url: URL
    private let language: String?
    private let speakers: SpeakerRequest
    private let transcriber: any TimedTranscribing
    private let dictation: any DictationActivity
    private let speakerProvider: any SpeakerTurnProviding
    private let openSource: @Sendable (URL) async throws -> any FileAudioSource
    private let pollInterval: Duration
    private var cancelRequested = false
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

    /// Stops after the chunk in flight; the text so far stays.
    func cancel() {
        cancelRequested = true
    }

    func run() async {
        guard transcriber.isModelLoaded else {
            phase = .failed(Message.noModel)
            return
        }
        let generation = transcriber.modelGeneration

        let source: any FileAudioSource
        do {
            source = try await openSource(url)
        } catch let error as AudioFileError {
            phase = .failed(error.message)
            return
        } catch {
            phase = .failed(AudioFileError.notReadable.message)
            return
        }

        var turns: [SpeakerTurn] = []
        if speakers != .none {
            phase = .identifyingSpeakers
            do {
                let count: Int? = if case .exactly(let number) = speakers { number } else { nil }
                turns = try await speakerProvider.turns(for: url, speakerCount: count)
            } catch {
                phase = .failed(Message.speakersFailed)
                return
            }
            if cancelRequested {
                phase = .cancelled
                return
            }
        }

        let duration = source.duration
        var words: [TimedWord] = []
        var chunker = AudioChunker()
        var fraction = 0.0
        phase = .transcribing(0)

        /// Transcribes one chunk; false when the job has ended (its phase says why).
        func transcribe(_ chunk: AudioChunk) async -> Bool {
            while dictation.isDictating {
                if cancelRequested { break }
                phase = .pausedForDictation(fraction)
                try? await Task.sleep(for: pollInterval)
            }
            if cancelRequested {
                phase = .cancelled
                return false
            }
            guard transcriber.isModelLoaded, transcriber.modelGeneration == generation else {
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
                phase = .failed(Message.stopped(error.localizedDescription))
                return false
            }
            paragraphs = TranscriptBuilder.paragraphs(words: words, turns: turns)
            let end = chunk.startSeconds + Double(chunk.samples.count) / Double(AudioChunker.sampleRate)
            fraction = duration > 0 ? min(1, max(fraction, end / duration)) : fraction
            if transcriber.modelGeneration != generation {
                phase = .failed(Message.modelChanged)
                return false
            }
            if cancelRequested {
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
            phase = .failed(AudioFileError.notReadable.message)
            return
        }
        if let last = chunker.finish() {
            guard await transcribe(last) else { return }
        }
        phase = paragraphs.isEmpty ? .failed(Message.noSpeech) : .finished
    }
}
