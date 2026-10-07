//
//  LiveTranscriptionSession.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 05/10/2026.
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

/// One live transcription, from the first captured sample to the last paragraph: audio from
/// one or two sources is cut into chunks as it arrives and transcribed in order, with the
/// paragraphs so far always available. Nothing is kept in memory for the length of the
/// recording except the words: the audio for the speaker pass goes to a temporary file.
///
/// Dictation goes first: a chunk waits while a dictation session is under way. With both
/// sources, the microphone's words are the user's ("You") and the system audio's are
/// "Others" until the speaker pass, at the end, tells them apart.
@Observable
final class LiveTranscriptionSession {
    enum Phase: Equatable {
        case idle
        case recording
        /// Stopped; the audio still queued is being transcribed.
        case finishing
        case identifyingSpeakers
        case finished
        case cancelled
        case failed(String)
    }

    enum Message {
        static let noModel = FileTranscriptionJob.Message.noModel
        static let modelChanged = FileTranscriptionJob.Message.modelChanged
        static let speakersFailed = "Couldn't identify speakers; the transcript keeps the labels it had"
        static let noSpeech = "No speech was heard"
        static func stopped(_ reason: String) -> String { "Transcription stopped: \(reason)" }
    }

    private(set) var phase: Phase = .idle {
        didSet { if phase != oldValue { onPhaseChange?(phase) } }
    }
    /// Called on the main actor after every change of `phase`, for the owner that is not a view.
    var onPhaseChange: ((Phase) -> Void)?
    private(set) var paragraphs: [TranscriptParagraph] = []
    /// Seconds of audio captured so far, from the source that has delivered the most.
    private(set) var elapsed: Double = 0
    /// Chunks waiting for the speech model.
    private(set) var backlog = 0
    /// A sentence about something that went wrong without ending the transcription.
    private(set) var notice: String?
    /// The whole recording, every source mixed, once the session has ended when it was asked to
    /// keep it. A temporary file: the owner moves it next to the saved transcript.
    private(set) var recordedAudio: URL?
    var text: String { TranscriptBuilder.text(paragraphs) }

    var isRunning: Bool {
        switch phase {
        case .recording, .finishing, .identifyingSpeakers: true
        case .idle, .finished, .cancelled, .failed: false
        }
    }

    let kinds: Set<LiveAudioKind>
    /// The source whose speakers the pass at the end tells apart: the system audio when it is
    /// recorded (the microphone is the user), otherwise the microphone. Nil without a pass.
    let diarizedKind: LiveAudioKind?

    /// The sources in a fixed order, microphone first.
    private var orderedKinds: [LiveAudioKind] { LiveAudioKind.allCases.filter(kinds.contains) }

    private struct Stream {
        var chunker: AudioChunker
        var source: (any LiveAudioSource)?
        var received = 0
        var words: [TimedWord] = []
    }

    private var streams: [LiveAudioKind: Stream] = [:]
    private var turns: [SpeakerTurn] = []
    private let language: String?
    private let speakers: SpeakerRequest
    private let transcriber: any TimedTranscribing
    private let dictation: any DictationActivity
    private let speakerProvider: any SpeakerTurnProviding
    private let makeSource: LiveAudioSourceFactory
    private let vocabulary: [VocabularyEntry]
    private let isDictionaryWord: (String) -> Bool
    private let pollInterval: Duration
    private var modelGeneration = 0

    private let chunks: AsyncStream<(LiveAudioKind, AudioChunk)>
    private let chunkFeed: AsyncStream<(LiveAudioKind, AudioChunk)>.Continuation
    /// The diarized source's audio on its way to `recorder`, in order.
    private let audio: AsyncStream<[Float]>
    private let audioFeed: AsyncStream<[Float]>.Continuation
    private let recorder: LiveAudioFile?
    private var worker: Task<Void, Never>?
    private var writer: Task<Void, Never>?
    /// The kept recording: the sources mixed, written as they arrive.
    private var mixer: LiveAudioMixer
    private let kept: AsyncStream<[Float]>
    private let keptFeed: AsyncStream<[Float]>.Continuation
    private let keeper: LiveAudioFile?
    private var keptWriter: Task<Void, Never>?

    init(
        kinds: Set<LiveAudioKind>, language: String?, speakers: SpeakerRequest,
        transcriber: any TimedTranscribing, dictation: any DictationActivity,
        speakerProvider: any SpeakerTurnProviding, makeSource: @escaping LiveAudioSourceFactory,
        vocabulary: [VocabularyEntry] = [],
        isDictionaryWord: @escaping (String) -> Bool = { DictionaryWords.isWord($0, language: nil) },
        chunkSeconds: (minimum: Int, maximum: Int) = (10, 15),
        audioDirectory: URL = FileManager.default.temporaryDirectory,
        keepAudio: Bool = false,
        pollInterval: Duration = .milliseconds(200)
    ) {
        self.kinds = kinds
        self.language = language
        self.speakers = speakers
        self.transcriber = transcriber
        self.dictation = dictation
        self.speakerProvider = speakerProvider
        self.makeSource = makeSource
        self.vocabulary = vocabulary
        self.isDictionaryWord = isDictionaryWord
        self.pollInterval = pollInterval
        let diarized: LiveAudioKind? = speakers == .none ? nil
            : kinds.contains(.systemAudio) ? .systemAudio
            : kinds.contains(.microphone) ? .microphone : nil
        diarizedKind = diarized
        recorder = diarized == nil ? nil : LiveAudioFile(directory: audioDirectory)
        (chunks, chunkFeed) = AsyncStream.makeStream(of: (LiveAudioKind, AudioChunk).self)
        (audio, audioFeed) = AsyncStream.makeStream(of: [Float].self)
        (kept, keptFeed) = AsyncStream.makeStream(of: [Float].self)
        keeper = keepAudio ? LiveAudioFile(directory: audioDirectory) : nil
        mixer = LiveAudioMixer(kinds: kinds)
        for kind in kinds {
            streams[kind] = Stream(chunker: AudioChunker(minimumSeconds: chunkSeconds.minimum, maximumSeconds: chunkSeconds.maximum))
        }
    }

    /// Starts every source. Throws, with nothing running, when one cannot start; the session
    /// can then be dropped.
    func start() throws {
        guard phase == .idle else { return }
        guard transcriber.isModelLoaded else {
            phase = .failed(Message.noModel)
            return
        }
        modelGeneration = transcriber.modelGeneration
        var started: [any LiveAudioSource] = []
        do {
            for kind in orderedKinds {
                let source = try makeSource(kind) { [weak self] samples in
                    // Serial and in order, as a dispatch to the main queue is; tasks are not.
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { self?.receive(samples, from: kind) }
                    }
                }
                try source.start()
                started.append(source)
                streams[kind]?.source = source
            }
        } catch {
            for source in started { source.stop() }
            for kind in kinds { streams[kind]?.source = nil }
            throw error
        }
        phase = .recording
        if let recorder {
            let audio = audio
            writer = Task {
                for await samples in audio { await recorder.append(samples) }
            }
        }
        if let keeper {
            let kept = kept
            keptWriter = Task {
                for await samples in kept { await keeper.append(samples) }
            }
        }
        worker = Task { await drain() }
    }

    /// Ends the recording; what is still queued is transcribed, then the speaker pass runs if
    /// one was asked for. The sources stop at once; the last of their audio, already on its way
    /// to the main queue, is taken in before the chunkers are flushed.
    func stop() {
        guard phase == .recording, !isStopping else { return }
        isStopping = true
        for stream in streams.values { stream.source?.stop() }
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.flush() }
        }
    }

    private var isStopping = false

    private func flush() {
        guard phase == .recording else { return }
        phase = .finishing
        for kind in orderedKinds {
            guard var stream = streams[kind] else { continue }
            if let last = stream.chunker.finish() { enqueue(kind, last) }
            streams[kind] = stream
        }
        if keeper != nil { keptFeed.yield(mixer.finish()) }
        chunkFeed.finish()
        audioFeed.finish()
        keptFeed.finish()
    }

    /// Ends everything at once; the transcript so far stays. Does nothing once ended.
    func cancel() {
        guard isRunning else { return }
        for stream in streams.values { stream.source?.stop() }
        chunkFeed.finish()
        audioFeed.finish()
        keptFeed.finish()
        worker?.cancel()
        phase = .cancelled
        if let recorder { Task { await recorder.discard() } }
        if let keeper { Task { await keeper.discard() } }
    }

    // MARK: - Audio in

    private func receive(_ samples: [Float], from kind: LiveAudioKind) {
        guard phase == .recording, var stream = streams[kind] else { return }
        stream.received += samples.count
        for chunk in stream.chunker.append(samples) { enqueue(kind, chunk) }
        streams[kind] = stream
        elapsed = max(elapsed, Double(stream.received) / Double(AudioChunker.sampleRate))
        if kind == diarizedKind { audioFeed.yield(samples) }
        if keeper != nil {
            let mixed = mixer.append(samples, from: kind)
            if !mixed.isEmpty { keptFeed.yield(mixed) }
        }
    }

    private func enqueue(_ kind: LiveAudioKind, _ chunk: AudioChunk) {
        backlog += 1
        chunkFeed.yield((kind, chunk))
    }

    // MARK: - Transcribing

    private func drain() async {
        for await (kind, chunk) in chunks {
            guard !Task.isCancelled else { return }
            let transcribed = await transcribe(chunk, from: kind)
            // Counted out only once it is done, so the backlog includes the chunk in flight.
            backlog -= 1
            guard transcribed else { break }
        }
        guard !Task.isCancelled else { return }
        if let failure {
            for stream in streams.values { stream.source?.stop() }
            audioFeed.finish()
            keptFeed.finish()
            if let recorder { await recorder.discard() }
            // What was recorded before the failure is kept with what was transcribed; the
            // failure is reported once that recording is closed, so its owner can save both.
            await finishKeptAudio()
            phase = .failed(failure)
            return
        }
        await identifySpeakersIfAsked()
        guard !Task.isCancelled else { return }
        await finishKeptAudio()
        guard !Task.isCancelled else { return }
        phase = .finished
    }

    /// Transcribes one chunk; false when the session has failed (its phase says why).
    private func transcribe(_ chunk: AudioChunk, from kind: LiveAudioKind) async -> Bool {
        while dictation.isDictating, !Task.isCancelled {
            try? await Task.sleep(for: pollInterval)
        }
        guard !Task.isCancelled else { return false }
        guard !modelChanged else {
            failure = Message.modelChanged
            return false
        }
        guard !LiveTranscript.isSilent(chunk.samples) else { return true }
        let label = LiveTranscript.label(for: kind, among: kinds)
        do {
            let words = try await transcriber.transcribeTimed(chunk.samples, language: language)
            let fixed = FileTranscriptionJob.applyVocabulary(words, entries: vocabulary, isDictionaryWord: isDictionaryWord)
            streams[kind]?.words += fixed.map {
                TimedWord(text: $0.text, start: $0.start + chunk.startSeconds, end: $0.end + chunk.startSeconds, speaker: label)
            }
        } catch {
            guard !Task.isCancelled else { return false }
            failure = modelChanged ? Message.modelChanged : Message.stopped(error.localizedDescription)
            return false
        }
        await rebuild()
        return true
    }

    /// Why transcribing stopped early; reported as the phase once the session has wound down.
    private var failure: String?

    /// Closes the kept recording once everything has been written to it.
    private func finishKeptAudio() async {
        guard let keeper else { return }
        await keptWriter?.value
        recordedAudio = await keeper.finish()
    }

    private var modelChanged: Bool {
        !transcriber.isModelLoaded || transcriber.modelGeneration != modelGeneration
    }

    private func identifySpeakersIfAsked() async {
        guard let diarizedKind, let recorder else { return }
        await writer?.value
        guard let url = await recorder.finish() else { return }
        defer { Task.detached { try? FileManager.default.removeItem(at: url) } }
        var count: Int?
        if case .exactly(let exact) = speakers { count = exact }
        phase = .identifyingSpeakers
        do {
            let found = try await speakerProvider.turns(for: url, speakerCount: count)
            guard !Task.isCancelled else { return }
            turns = found
            // The diarized source's words now go by the turns; the other source keeps its label.
            let unlabelled = (streams[diarizedKind]?.words ?? []).map {
                var word = $0
                word.speaker = nil
                return word
            }
            streams[diarizedKind]?.words = unlabelled
            await rebuild()
        } catch {
            guard !Task.isCancelled else { return }
            notice = Message.speakersFailed
        }
    }

    /// Off the main actor: with many words a rebuild takes long enough to delay a hotkey.
    private func rebuild() async {
        let words = LiveTranscript.merged(orderedKinds.compactMap { streams[$0]?.words })
        let built = await Self.buildParagraphs(words: words, turns: turns)
        guard !Task.isCancelled else { return }
        paragraphs = built
    }

    @concurrent
    private static func buildParagraphs(words: [TimedWord], turns: [SpeakerTurn]) async -> [TranscriptParagraph] {
        TranscriptBuilder.paragraphs(words: words, turns: turns, names: LiveTranscript.names)
    }
}
