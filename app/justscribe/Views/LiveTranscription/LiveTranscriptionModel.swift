//
//  LiveTranscriptionModel.swift
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

import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

/// The state behind the Live Transcription window: which audio to record, whether to tell
/// speakers apart, the current session, and the actions on its transcript. Nothing here
/// outlives the window.
@Observable
final class LiveTranscriptionModel {
    static let useMicrophoneKey = "liveTranscription.useMicrophone"
    static let useSystemAudioKey = "liveTranscription.useSystemAudio"
    static let identifySpeakersKey = "liveTranscription.identifySpeakers"
    /// Keep the recording of a Live Transcription or Long Dictation next to its transcript.
    /// Off unless turned on, in Settings or in the Live Transcription window.
    static let keepAudioKey = "transcripts.keepAudio"

    enum Notice {
        static let speakerDownloadFailed = FileTranscriptionModel.Notice.speakerDownloadFailed
        static let microphoneDenied = "Microphone access is needed to record what you say. Allow it in System Settings → Privacy & Security → Microphone."
        static let saved = "Saved to Transcripts"
        static func saveFailed(_ reason: String) -> String { "Couldn't save the transcript: \(reason)" }
    }

    /// What the status line shows for a session.
    enum Status: Equatable {
        case recording
        case working(String)
        case ended(String, systemImage: String)
    }

    /// Record what the user says. On unless turned off.
    var useMicrophone: Bool {
        didSet { defaults.set(useMicrophone, forKey: Self.useMicrophoneKey) }
    }
    /// Record what the other apps play.
    var useSystemAudio: Bool {
        didSet { defaults.set(useSystemAudio, forKey: Self.useSystemAudioKey) }
    }
    /// Tell speakers apart at the end. Turning it on fetches the speaker models the first time.
    var identifySpeakers: Bool {
        didSet {
            guard identifySpeakers != oldValue else { return }
            defaults.set(identifySpeakers, forKey: Self.identifySpeakersKey)
            prepareSpeakerModelsIfNeeded()
        }
    }
    /// The number of speakers as typed; empty means "work it out".
    var speakerCountText = ""
    private(set) var session: LiveTranscriptionSession?
    /// A sentence to show under the options: a failed download, a refused permission, a source
    /// that could not start.
    private(set) var notice: String?
    /// Between pressing Start and the session running: the permission prompt may be up.
    private(set) var isStarting = false

    let diarization: any SpeakerModelProviding
    private let transcriber: any TimedTranscribing
    private let dictation: any DictationActivity
    private let defaults: UserDefaults
    private let makeSource: LiveAudioSourceFactory
    private let requestMicrophone: () async -> Bool
    private let audioDirectory: URL
    /// Writes a finished transcript (text, title, recording) to Transcripts; the app's goes to
    /// `TranscriptStore`.
    private let saveTranscript: (String, String, URL?) throws -> Void

    init(
        transcriber: any TimedTranscribing, dictation: any DictationActivity,
        diarization: any SpeakerModelProviding = SpeakerDiarizationService.shared,
        defaults: UserDefaults = .standard,
        makeSource: @escaping LiveAudioSourceFactory = LiveTranscriptionModel.makeSource,
        requestMicrophone: @escaping () async -> Bool = LiveTranscriptionModel.requestMicrophone,
        audioDirectory: URL = FileManager.default.temporaryDirectory,
        saveTranscript: @escaping (String, String, URL?) throws -> Void = { try TranscriptStore.shared.save($0, title: $1, audio: $2) }
    ) {
        self.transcriber = transcriber
        self.dictation = dictation
        self.diarization = diarization
        self.defaults = defaults
        self.makeSource = makeSource
        self.requestMicrophone = requestMicrophone
        self.audioDirectory = audioDirectory
        self.saveTranscript = saveTranscript
        useMicrophone = defaults.object(forKey: Self.useMicrophoneKey) == nil ? true : defaults.bool(forKey: Self.useMicrophoneKey)
        useSystemAudio = defaults.bool(forKey: Self.useSystemAudioKey)
        identifySpeakers = defaults.bool(forKey: Self.identifySpeakersKey)
        prepareSpeakerModelsIfNeeded()
    }

    var hasModel: Bool { transcriber.isModelLoaded }
    var kinds: Set<LiveAudioKind> {
        var kinds = Set<LiveAudioKind>()
        if useMicrophone { kinds.insert(.microphone) }
        if useSystemAudio { kinds.insert(.systemAudio) }
        return kinds
    }
    var speakerRequest: SpeakerRequest {
        FileTranscriptionModel.speakerRequest(identify: identifySpeakers, countText: speakerCountText)
    }

    /// Whether a transcription can start: a model is loaded, at least one source is on, the
    /// speaker model is not still downloading, and nothing is running or starting.
    var canStart: Bool {
        hasModel && !kinds.isEmpty && diarization.downloadProgress == nil && !isStarting && session?.isRunning != true
    }

    /// The caption under the speaker toggle, which depends on what is recorded.
    nonisolated static func speakerCaption(kinds: Set<LiveAudioKind>) -> String {
        if kinds == [.microphone, .systemAudio] {
            return "You are labelled from the microphone. The speakers in the system audio are told apart when the recording stops, with a small extra model, downloaded once."
        }
        return "Labels who said what when the recording stops. Uses a small extra model, downloaded once."
    }

    /// The caption under the speaker count: with the microphone as the user, the count is of
    /// the others.
    nonisolated static func speakerCountHint(for countText: String, kinds: Set<LiveAudioKind>) -> String {
        let hint = FileTranscriptionModel.speakerCountHint(for: countText)
        guard kinds == [.microphone, .systemAudio], hint == FileTranscriptionModel.SpeakerCountHint.normal else { return hint }
        return "Not counting you. Leave empty to detect, or enter 1 to 10."
    }

    /// The status line for a session in `phase`; `backlog` is how many chunks wait for the model.
    nonisolated static func status(phase: LiveTranscriptionSession.Phase, backlog: Int, hasText: Bool) -> Status {
        switch phase {
        case .idle, .recording:
            return .recording
        case .finishing:
            return .working(backlog > 1 ? "Transcribing the last \(backlog) pieces…" : "Transcribing the last of the audio…")
        case .identifyingSpeakers:
            return .working("Identifying speakers…")
        case .finished:
            return hasText ? .ended("Done", systemImage: "checkmark.circle.fill")
                : .ended(LiveTranscriptionSession.Message.noSpeech, systemImage: "waveform.slash")
        case .cancelled:
            return .ended("Stopped", systemImage: "xmark.circle")
        case .failed(let message):
            return .ended(message, systemImage: "exclamationmark.triangle.fill")
        }
    }

    static func status(of session: LiveTranscriptionSession) -> Status {
        status(phase: session.phase, backlog: session.backlog, hasText: !session.paragraphs.isEmpty)
    }

    /// "Live Transcription 2026-10-05 at 14.32.txt"
    nonisolated static func saveName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm"
        return "Live Transcription \(formatter.string(from: date)).txt"
    }

    /// Starts recording with the options as set. Asks for microphone access first when the
    /// microphone is on and access has not been given. Ignored while a session runs.
    func start() {
        guard canStart else { return }
        notice = nil
        isStarting = true
        Task {
            defer { isStarting = false }
            if useMicrophone {
                guard await requestMicrophone() else {
                    notice = Notice.microphoneDenied
                    return
                }
            }
            let language = defaults.string(forKey: AppSettings.selectedLanguageKey)
            let session = LiveTranscriptionSession(
                kinds: kinds, language: language, speakers: speakerRequest,
                transcriber: transcriber, dictation: dictation, speakerProvider: diarization,
                makeSource: makeSource,
                vocabulary: VocabularyStore.shared.entries,
                isDictionaryWord: { DictionaryWords.isWord($0, language: language) },
                audioDirectory: audioDirectory,
                keepAudio: defaults.bool(forKey: Self.keepAudioKey))
            session.onPhaseChange = { [weak self, weak session] phase in
                guard phase == .finished, let self, let session, session === self.session else { return }
                self.saveFinished(session)
            }
            do {
                try session.start()
                self.session = session
            } catch {
                notice = error.localizedDescription
            }
        }
    }

    /// The title a saved live transcription gets.
    nonisolated static func transcriptTitle(kinds: Set<LiveAudioKind>) -> String {
        kinds == [.systemAudio] ? "System Audio" : "Live Transcription"
    }

    /// Writes the finished transcript to Transcripts, with timestamps and speaker labels as
    /// the window shows them, and the recording when one was kept. Without speech or a
    /// recording nothing is written.
    private func saveFinished(_ session: LiveTranscriptionSession) {
        let text = session.text
        guard !text.isEmpty || session.recordedAudio != nil else { return }
        do {
            try saveTranscript(text, Self.transcriptTitle(kinds: session.kinds), session.recordedAudio)
            notice = Notice.saved
        } catch {
            notice = Notice.saveFailed(error.localizedDescription)
        }
    }

    func stop() {
        session?.stop()
    }

    /// Back to the options; the transcript is gone. Ignored while a session runs.
    func reset() {
        guard session?.isRunning != true else { return }
        session = nil
        notice = nil
    }

    /// Back to the options at once, ending a running session. Nothing of it is kept.
    func discard() {
        session?.cancel()
        session = nil
        notice = nil
    }

    func copy() {
        guard let text = session?.text, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func save() {
        guard let session, !session.text.isEmpty else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Self.saveName(for: Date())
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try session.text.write(to: destination, atomically: true, encoding: .utf8)
        } catch {
            notice = Notice.saveFailed(error.localizedDescription)
        }
    }

    /// Fetches the speaker models when speakers are on and the models are not ready, so the
    /// download happens here, with its own progress and failure, rather than inside a session.
    func prepareSpeakerModelsIfNeeded() {
        guard identifySpeakers, !diarization.isReady, diarization.downloadProgress == nil else { return }
        notice = nil
        Task {
            do {
                try await diarization.prepare()
            } catch {
                notice = Notice.speakerDownloadFailed
                identifySpeakers = false
            }
        }
    }

    // MARK: - The app's sources

    /// The microphone the saved priority picks, or the system-audio tap.
    static func makeSource(_ kind: LiveAudioKind, sink: @escaping LiveAudioSink) throws -> any LiveAudioSource {
        switch kind {
        case .microphone:
            let capture = AudioCaptureService.shared
            capture.refreshDevices()
            let priority = UserDefaults.standard.stringArray(forKey: AppSettings.microphonePriorityKey) ?? []
            let banned = UserDefaults.standard.stringArray(forKey: AppSettings.bannedMicrophoneIDsKey) ?? []
            guard let device = MicrophoneDevice.preferred(in: capture.availableDevices, priority: priority, banned: banned) else {
                throw LiveAudioError.noMicrophone
            }
            return MicrophoneStream(deviceID: device.id, sink: sink)
        case .systemAudio:
            return SystemAudioTap(sink: sink)
        }
    }

    /// Whether the microphone may be used, asking when it has not been decided.
    static func requestMicrophone() async -> Bool {
        let permissions = PermissionsService.shared
        permissions.checkMicrophonePermission()
        if permissions.microphoneStatus == .granted { return true }
        NSApp.activate(ignoringOtherApps: true)
        return await permissions.requestMicrophonePermission()
    }
}
