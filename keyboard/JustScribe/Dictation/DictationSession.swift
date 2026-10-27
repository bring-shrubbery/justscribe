//
//  DictationSession.swift
//  JustScribeKeyboard
//
//  Created by Antoni Silvestrovic on 22/10/2026.
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

import AVFoundation
import Observation
import UIKit

/// The app's side of keyboard dictation. A session keeps the microphone open in
/// the background (the orange dot shows) so the keyboard can start and stop
/// recordings without bringing the app forward. It runs until the user ends it;
/// an interruption such as a phone call pauses it, and it resumes afterwards.
@MainActor @Observable
final class DictationSession {

    static let shared = DictationSession()

    enum SpeechStatus: Equatable {
        case notPrepared
        case preparing
        case ready
        case failed(String)
    }

    private(set) var isLive = false
    private(set) var phase: DictationPhase = .idle
    private(set) var speechStatus: SpeechStatus = .notPrepared
    private(set) var level: Float = 0
    private(set) var lastTranscript: String?
    private(set) var errorMessage: String?

    @ObservationIgnored private let bridge = DictationBridge()
    @ObservationIgnored private lazy var microphone = MicrophoneEngine { [bridge] level in
        bridge?.publish(level: level)
        Task { @MainActor in DictationSession.shared.level = level }
    }
    @ObservationIgnored private var configuration: SpeechRecognition.Configuration?
    @ObservationIgnored private var run: TranscriptionRun?
    @ObservationIgnored private var heartbeat: Timer?
    @ObservationIgnored private var observers: [DarwinNotificationObserver] = []
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?

    private init() {
        observers = [
            DarwinNotificationObserver(name: DictationCommand.start.notificationName) { DictationSession.shared.startRecording() },
            DarwinNotificationObserver(name: DictationCommand.stop.notificationName) { Task { await DictationSession.shared.stopRecording() } },
            DarwinNotificationObserver(name: DictationCommand.cancel.notificationName) { Task { await DictationSession.shared.cancelRecording() } },
        ]
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let began = raw == AVAudioSession.InterruptionType.began.rawValue
            MainActor.assumeIsolated {
                if began {
                    DictationSession.shared.pauseForInterruption()
                } else {
                    DictationSession.shared.resumeAfterInterruption()
                }
            }
        }
        // A session never survives the app: anything left over is from a run that was killed.
        bridge?.publishHeartbeat(nil)
        bridge?.publish(phase: .idle)
    }

    // MARK: - Speech

    func prepareSpeech() async {
        guard speechStatus != .preparing, speechStatus != .ready else { return }
        speechStatus = .preparing
        do {
            configuration = try await SpeechRecognition.prepare()
            speechStatus = .ready
        } catch {
            speechStatus = .failed(error.localizedDescription)
        }
    }

    // MARK: - Session

    /// Opens the microphone and goes live. With `recordNow`, a recording starts
    /// as soon as it is open: the keyboard opened the app to dictate.
    func begin(recordNow: Bool) async {
        errorMessage = nil
        if !isLive {
            guard await AVAudioApplication.requestRecordPermission() else {
                fail("JustScribe needs the microphone. Allow it in Settings.")
                return
            }
            await prepareSpeech()
            guard configuration != nil else {
                if case .failed(let message) = speechStatus { fail(message) }
                return
            }
            do {
                try openMicrophone()
            } catch {
                fail("The microphone did not start: \(error.localizedDescription)")
                return
            }
            isLive = true
            startHeartbeat()
        }
        if recordNow { startRecording() }
    }

    /// Closes the microphone; the keyboard opens the app again next time.
    func end() {
        heartbeat?.invalidate()
        heartbeat = nil
        if let run {
            self.run = nil
            Task { await run.cancel() }
        }
        microphone.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isLive = false
        setPhase(.idle)
        bridge?.publishHeartbeat(nil)
    }

    private func openMicrophone() throws {
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
        try audio.setActive(true)
        try microphone.start()
    }

    // MARK: - Interruptions

    /// A call or another app took the microphone: drop any recording, keep the session.
    func pauseForInterruption() {
        guard isLive else { return }
        if run != nil { Task { await cancelRecording() } }
    }

    /// The interruption ended: reopen the microphone, or end the session if iOS refuses.
    func resumeAfterInterruption() {
        guard isLive else { return }
        do {
            try openMicrophone()
        } catch {
            end()
        }
    }

    // MARK: - Recording

    func startRecording() {
        guard isLive, let configuration, phase == .idle else { return }
        do {
            let run = try TranscriptionRun(configuration: configuration, inputFormat: microphone.inputFormat)
            self.run = run
            microphone.route(to: run)
            setPhase(.recording)
        } catch {
            fail(error.localizedDescription)
        }
    }

    func stopRecording() async {
        guard phase == .recording, let run else { return }
        microphone.route(to: nil)
        self.run = nil
        setPhase(.transcribing)
        do {
            let text = try await run.finish()
            lastTranscript = text
            if !text.isEmpty { bridge?.publish(result: text) }
        } catch {
            fail("Transcription failed: \(error.localizedDescription)")
        }
        setPhase(.idle)
    }

    func cancelRecording() async {
        guard let run else { return }
        microphone.route(to: nil)
        self.run = nil
        setPhase(.idle)
        await run.cancel()
    }

    // MARK: - Private

    private func setPhase(_ phase: DictationPhase) {
        self.phase = phase
        if phase != .recording { level = 0 }
        bridge?.publish(phase: phase)
    }

    private func fail(_ message: String) {
        errorMessage = message
        bridge?.publish(error: message)
    }

    private func startHeartbeat() {
        heartbeat?.invalidate()
        bridge?.publishHeartbeat()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [bridge] _ in
            bridge?.publishHeartbeat()
        }
    }
}
