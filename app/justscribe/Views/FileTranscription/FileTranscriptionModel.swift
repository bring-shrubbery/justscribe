//
//  FileTranscriptionModel.swift
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

import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

/// The state behind the Transcribe File window: the options, the current job, and the
/// actions on its result. Nothing here outlives the window.
@Observable
final class FileTranscriptionModel {
    static let identifySpeakersKey = "fileTranscription.identifySpeakers"

    /// What the status line under the file name shows.
    enum Status: Equatable {
        /// The job is under way; `progress` is nil when there is no fraction to show.
        case working(String, progress: Double?)
        case ended(String, systemImage: String)
    }

    /// Whether to label speakers. Remembered between launches; turning it on fetches the
    /// speaker models the first time.
    var identifySpeakers: Bool {
        didSet {
            guard identifySpeakers != oldValue else { return }
            UserDefaults.standard.set(identifySpeakers, forKey: Self.identifySpeakersKey)
            if identifySpeakers { prepareSpeakerModels() }
        }
    }
    /// The number of speakers as typed; empty means "work it out".
    var speakerCountText = ""
    private(set) var job: FileTranscriptionJob?
    /// A sentence to show under the options: a failed download, or a file that was refused.
    private(set) var notice: String?

    let diarization: SpeakerDiarizationService
    private let transcriber: any TimedTranscribing
    private let dictation: any DictationActivity

    init(
        transcriber: any TimedTranscribing, dictation: any DictationActivity,
        diarization: SpeakerDiarizationService = .shared
    ) {
        self.transcriber = transcriber
        self.dictation = dictation
        self.diarization = diarization
        identifySpeakers = UserDefaults.standard.bool(forKey: Self.identifySpeakersKey)
    }

    var hasModel: Bool { transcriber.isModelLoaded }
    var speakerRequest: SpeakerRequest { Self.speakerRequest(identify: identifySpeakers, countText: speakerCountText) }

    nonisolated static func speakerRequest(identify: Bool, countText: String) -> SpeakerRequest {
        guard identify else { return .none }
        if let count = Int(countText.trimmingCharacters(in: .whitespaces)), (1...10).contains(count) {
            return .exactly(count)
        }
        return .detect
    }

    nonisolated static func saveName(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent + ".txt"
    }

    /// The status line for a job in `phase`. A job that has been created but whose file is
    /// still opening is in `.idle`; a pending cancel outranks the phase it interrupts.
    static func status(phase: FileTranscriptionJob.Phase, isCancelling: Bool, isDurationKnown: Bool) -> Status {
        if isCancelling { return .working("Stopping…", progress: nil) }
        switch phase {
        case .idle:
            return .working("Opening…", progress: nil)
        case .identifyingSpeakers:
            return .working("Identifying speakers…", progress: nil)
        case .transcribing(let fraction):
            guard isDurationKnown else { return .working("Transcribing…", progress: nil) }
            return .working("Transcribing… \(Int(fraction * 100))%", progress: fraction)
        case .pausedForDictation(let fraction):
            return .working("Paused while you dictate", progress: isDurationKnown ? fraction : nil)
        case .finished:
            return .ended("Done", systemImage: "checkmark.circle.fill")
        case .cancelled:
            return .ended("Cancelled", systemImage: "xmark.circle")
        case .failed(let message):
            return .ended(message, systemImage: "exclamationmark.triangle.fill")
        }
    }

    static func status(of job: FileTranscriptionJob) -> Status {
        status(phase: job.phase, isCancelling: job.isCancelling, isDurationKnown: job.isDurationKnown)
    }

    /// Starts transcribing `url`, with speakers as the options say. The URL is used as
    /// given: the sandbox's access to a chosen or dropped file is tied to that URL.
    func open(_ url: URL) {
        start(url, speakers: speakerRequest)
    }

    /// Runs the same file again without the speaker pass, after that pass failed.
    func retryWithoutSpeakers() {
        guard let url = job?.url else { return }
        start(url, speakers: .none)
    }

    private func start(_ url: URL, speakers: SpeakerRequest) {
        guard job?.isRunning != true else { return }
        notice = nil
        let language = UserDefaults.standard.string(forKey: AppSettings.selectedLanguageKey)
        let job = FileTranscriptionJob(
            url: url, language: language, speakers: speakers,
            transcriber: transcriber, dictation: dictation, speakerProvider: diarization)
        self.job = job
        job.start()
    }

    func cancel() {
        job?.cancel()
    }

    /// Back to the drop zone; the transcript is gone.
    func reset() {
        guard job?.isRunning != true else { return }
        job = nil
        notice = nil
    }

    func copy() {
        guard let text = job?.text, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func save() {
        guard let job, !job.text.isEmpty else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Self.saveName(for: job.url)
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try job.text.write(to: destination, atomically: true, encoding: .utf8)
        } catch {
            notice = "Couldn't save the transcript: \(error.localizedDescription)"
        }
    }

    private func prepareSpeakerModels() {
        guard !diarization.isReady else { return }
        notice = nil
        Task {
            do {
                try await diarization.prepare()
            } catch {
                notice = "Couldn't download the speaker model. Check your connection and try again"
                identifySpeakers = false
            }
        }
    }
}
