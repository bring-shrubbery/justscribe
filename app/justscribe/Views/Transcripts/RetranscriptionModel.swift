//
//  RetranscriptionModel.swift
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

/// Transcribes a saved transcript's recording again, with a model of the user's choosing, and
/// saves the result as a new transcript next to the original (sharing its recording), so the
/// two can be compared. Owned by the Transcripts window; one run at a time. The chosen model
/// replaces the loaded one while it runs, and the user's own model is loaded back afterwards.
@Observable
final class RetranscriptionModel {
    enum Notice {
        static let speakerDownloadFailed = FileTranscriptionModel.Notice.speakerDownloadFailed
        static func modelFailed(_ reason: String) -> String { "The model didn't load — \(reason)" }
        static func saveFailed(_ reason: String) -> String { "Couldn't save the transcript: \(reason)" }
    }

    /// What happens before the file job starts.
    enum Preparation: Equatable {
        case speakerModel
        case model(String)
    }

    /// The transcript being transcribed again, while a run is under way.
    private(set) var transcript: SavedTranscript?
    private(set) var preparation: Preparation?
    private(set) var job: FileTranscriptionJob?
    /// Why the last run ended short, shown under the transcript it was for.
    private(set) var notice: String?
    private(set) var noticeURL: URL?
    /// Whether to label speakers; starts as the Transcribe File window has it, and is not
    /// remembered.
    var identifySpeakers: Bool
    var speakerCountText = ""

    var isRunning: Bool { transcript != nil }

    /// The status line for the run: what is being prepared, then the job's own progress.
    var status: FileTranscriptionModel.Status? {
        if let job { return FileTranscriptionModel.status(of: job) }
        switch preparation {
        case .speakerModel: return .working("Downloading the speaker model…", progress: nil)
        case .model(let name): return .working("Loading \(name)…", progress: nil)
        case nil: return nil
        }
    }

    /// The models on disk, in the order the app lists them.
    var models: [UnifiedModelInfo] { availableModels() }
    var speakerRequest: SpeakerRequest {
        FileTranscriptionModel.speakerRequest(identify: identifySpeakers, countText: speakerCountText)
    }

    let store: TranscriptStore
    let diarization: any SpeakerModelProviding
    private let transcriber: any TimedTranscribing
    private let dictation: any DictationActivity
    private let defaults: UserDefaults
    private let availableModels: @MainActor () -> [UnifiedModelInfo]
    /// The model loaded now, so the picker starts on it.
    let loadedModelID: @MainActor () -> String?
    private let loadModel: @MainActor (String) async throws -> Void
    /// Loads the user's own model back, when the run used another.
    private let restoreModel: @MainActor () async -> Void
    private let openSource: @Sendable (URL) async throws -> any FileAudioSource
    private let pollInterval: Duration
    private var task: Task<Void, Never>?
    private var isCancelled = false

    init(
        store: TranscriptStore, transcriber: any TimedTranscribing, dictation: any DictationActivity,
        diarization: any SpeakerModelProviding = SpeakerDiarizationService.shared,
        defaults: UserDefaults = .standard,
        availableModels: @escaping @MainActor () -> [UnifiedModelInfo] = RetranscriptionModel.downloadedModels,
        loadedModelID: @escaping @MainActor () -> String? = { TranscriptionService.shared.loadedModelID },
        loadModel: @escaping @MainActor (String) async throws -> Void = { try await TranscriptionService.shared.loadModel(unifiedID: $0) },
        restoreModel: @escaping @MainActor () async -> Void = RetranscriptionModel.loadSelectedModel,
        openSource: @escaping @Sendable (URL) async throws -> any FileAudioSource = { try await AudioFileDecoder.open($0) },
        pollInterval: Duration = .milliseconds(200)
    ) {
        self.store = store
        self.transcriber = transcriber
        self.dictation = dictation
        self.diarization = diarization
        self.defaults = defaults
        self.availableModels = availableModels
        self.loadedModelID = loadedModelID
        self.loadModel = loadModel
        self.restoreModel = restoreModel
        self.openSource = openSource
        self.pollInterval = pollInterval
        identifySpeakers = defaults.bool(forKey: FileTranscriptionModel.identifySpeakersKey)
    }

    static func downloadedModels() -> [UnifiedModelInfo] {
        let downloaded = ModelDownloadService.shared.downloadedModels
        return UnifiedModelInfo.allModels.filter { downloaded.contains($0.id) }
    }

    /// Loads the model chosen in Settings, unless it is loaded already or not on disk.
    static func loadSelectedModel() async {
        let service = TranscriptionService.shared
        guard let id = UserDefaults.standard.string(forKey: AppSettings.selectedModelIDKey), !id.isEmpty,
              ModelDownloadService.shared.isModelDownloaded(id), service.loadedModelID != id else { return }
        try? await service.loadModel(unifiedID: id)
    }

    /// "Long Dictation (Whisper Large v3)". A title that already names a model loses that
    /// name first, so a transcript made from a re-transcription does not stack them.
    nonisolated static func title(for original: String, model: UnifiedModelInfo) -> String {
        var base = original.trimmingCharacters(in: .whitespaces)
        for known in UnifiedModelInfo.allModels {
            let suffix = " (\(known.displayName))"
            if base.hasSuffix(suffix) {
                base = String(base.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        return "\(base) (\(model.displayName))"
    }

    /// Transcribes `transcript`'s recording with `model`. Ignored while a run is under way,
    /// and for a transcript without a recording.
    func start(_ transcript: SavedTranscript, model: UnifiedModelInfo, speakers: SpeakerRequest) {
        guard !isRunning, let audio = transcript.audioURL else { return }
        self.transcript = transcript
        notice = nil
        noticeURL = nil
        isCancelled = false
        task = Task { @MainActor in
            await run(transcript, audio: audio, model: model, speakers: speakers)
        }
    }

    /// Ends the run: a job stops after its chunk in flight; a model load cannot be stopped, so
    /// the job is not started once it is done.
    func cancel() {
        guard isRunning else { return }
        isCancelled = true
        job?.cancel()
    }

    private func run(_ transcript: SavedTranscript, audio: URL, model: UnifiedModelInfo, speakers: SpeakerRequest) async {
        defer {
            self.transcript = nil
            preparation = nil
            job = nil
        }
        if speakers != .none, !diarization.isReady {
            preparation = .speakerModel
            do {
                try await diarization.prepare()
            } catch {
                fail(Notice.speakerDownloadFailed, for: transcript)
                return
            }
            if isCancelled { return }
        }
        preparation = .model(model.displayName)
        do {
            try await loadModel(model.id)
        } catch {
            fail(Notice.modelFailed(error.localizedDescription), for: transcript)
            await restoreModel()
            return
        }
        preparation = nil
        if isCancelled {
            await restoreModel()
            return
        }

        let language = defaults.string(forKey: AppSettings.selectedLanguageKey)
        let job = FileTranscriptionJob(
            url: audio, language: language, speakers: speakers,
            transcriber: transcriber, dictation: dictation, speakerProvider: diarization,
            vocabulary: VocabularyStore.shared.entries,
            isDictionaryWord: { DictionaryWords.isWord($0, language: language) },
            openSource: openSource, pollInterval: pollInterval)
        self.job = job
        await job.run()
        switch job.phase {
        case .finished:
            save(job.text, for: transcript, model: model)
        case .failed(let message):
            fail(message, for: transcript)
        case .idle, .identifyingSpeakers, .transcribing, .pausedForDictation, .cancelled:
            break
        }
        self.job = nil
        await restoreModel()
    }

    /// Writes the new transcript, dated like the original and sharing its recording, and asks
    /// the window to show it.
    private func save(_ text: String, for transcript: SavedTranscript, model: UnifiedModelInfo) {
        do {
            let saved = try store.save(
                text, title: Self.title(for: transcript.title, model: model), date: transcript.date,
                audio: transcript.audioURL, transfer: .copy)
            store.requestedSelection = saved.url
        } catch {
            fail(Notice.saveFailed(error.localizedDescription), for: transcript)
        }
    }

    private func fail(_ message: String, for transcript: SavedTranscript) {
        notice = message
        noticeURL = transcript.url
    }
}
