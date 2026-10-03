//
//  AppDelegate.swift
//  justscribe
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

import AppKit
import ApplicationServices
import SwiftUI

private struct TranscriptionTimeoutError: Error {}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private lazy var fileTranscription = FileTranscriptionWindowController(
        model: FileTranscriptionModel(transcriber: TranscriptionService.shared, dictation: self),
        openSettings: { [weak self] in self?.openSettings() }
    )
    private lazy var history = HistoryWindowController(
        store: HistoryStore.shared,
        openSettings: { [weak self] in self?.openSettings() }
    )

    private enum RecordingSessionState { case idle, recording, finalizing }
    private var sessionState: RecordingSessionState = .idle

    func applicationDidFinishLaunching(_ notification: Notification) {
        applySavedVisibilitySettings()
        checkInputMonitoringAndSetupHotkey()
        loadSelectedModel()
        loadGrammarModelIfEnabled()
        setupNotificationObservers()
        _ = UpdateService.shared // starts Sparkle's scheduled checks
        HistoryStore.shared.load()
        DiagnosticsLog.shared.load()
        VocabularyStore.shared.load()
        ModeStore.shared.load()
        // A speaker pass cut short by a quit or a crash leaves a copy of a file's audio behind.
        Task(priority: .background) { await SpeakerDiarizationService.shared.cleanUpLeftoverAudio() }
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStatusBarVisibilityChange),
            name: Notification.Name("updateStatusBarVisibility"),
            object: nil
        )
    }

    @objc private func handleStatusBarVisibilityChange(_ notification: Notification) {
        guard let show = notification.userInfo?["show"] as? Bool else { return }
        updateStatusBarVisibility(showInStatusBar: show)
    }

    // MARK: - Visibility Settings

    private func applySavedVisibilitySettings() {
        // Apply dock visibility (default to true if not set)
        let showInDock = UserDefaults.standard.object(forKey: AppSettings.showInDockKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: AppSettings.showInDockKey)
        updateDockVisibility(showInDock: showInDock)

        // Apply status bar visibility (default to true if not set)
        let showInStatusBar = UserDefaults.standard.object(forKey: AppSettings.showInStatusBarKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: AppSettings.showInStatusBarKey)
        if showInStatusBar {
            setupStatusBar()
        }
    }

    // MARK: - Permissions

    private func checkInputMonitoringAndSetupHotkey() {
        // Set up hotkey immediately - KeyboardShortcuts uses Carbon Events
        // which work without special permissions in sandboxed apps
        setupHotkey()
    }

    // MARK: - Model Loading

    private func loadSelectedModel() {
        guard let modelID = UserDefaults.standard.string(forKey: AppSettings.selectedModelIDKey),
              !modelID.isEmpty else {
            print("No model selected, skipping auto-load")
            return
        }

        // Load the model asynchronously after refreshing downloaded models list
        Task { @MainActor in
            // Refresh downloaded models first to ensure accurate check
            let downloadService = ModelDownloadService.shared
            await downloadService.refreshDownloadedModels()

            guard downloadService.isModelDownloaded(modelID) else {
                print("Selected model '\(modelID)' is not downloaded, skipping auto-load")
                return
            }

            do {
                print("Auto-loading model: \(modelID)")
                try await TranscriptionService.shared.loadModel(unifiedID: modelID)
                print("Model loaded successfully")
            } catch {
                print("Failed to auto-load model: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Grammar Model Loading

    private func loadGrammarModelIfEnabled() {
        let enabled = UserDefaults.standard.bool(forKey: AppSettings.grammarCorrectionEnabledKey)
        guard enabled else {
            print("Grammar correction disabled, skipping LLM load")
            return
        }

        let selectedID = UserDefaults.standard.string(forKey: AppSettings.selectedGrammarModelIDKey) ?? ""
        guard !selectedID.isEmpty else {
            print("Grammar correction enabled but no model selected, skipping LLM load")
            return
        }

        Task { @MainActor in
            guard GrammarCorrectionService.shared.isReadyToUse(selectedID) else {
                print("Grammar correction model \(selectedID) not downloaded, skipping auto-load")
                return
            }
            do {
                print("Auto-loading grammar correction model: \(selectedID)")
                try await GrammarCorrectionService.shared.loadModel(modelID: selectedID)
                print("Grammar correction model loaded successfully")
            } catch {
                print("Failed to auto-load grammar correction model: \(error.localizedDescription)")
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Unload models to free memory
        // This is called on the main thread by AppKit, so we can safely access MainActor-isolated code
        MainActor.assumeIsolated {
            TranscriptionService.shared.unloadModel()
            GrammarCorrectionService.shared.unloadModel()
            print("Models unloaded on app termination")
        }
    }

    // MARK: - Hotkey Setup

    /// Tracks how much text has been typed during streaming (for incremental typing)
    private var typedTextLength = 0
    /// How this session's text reaches the focused app, read once at key down so a change in
    /// Settings mid-dictation cannot leave half-typed text behind.
    private var insertionMode = TextInsertionMode.defaultMode
    /// Read at key down and kept for the session, so a change in Settings mid-dictation cannot
    /// orphan a press-mode recording or switch the mode under it.
    private var sessionTrigger = RecordingTrigger.defaultTrigger
    private var sessionContext: DictationContext?
    private var stoppedBySafety = false
    /// The system Accessibility prompt is shown once per launch, the first time a dictation
    /// cannot be inserted.
    private var didAskForAccessibility = false
    /// When the current session's recording began (for diagnostics).
    private var sessionStartedAt = Date()
    private var safetyStopTask: Task<Void, Never>?
    private static let safetyStop: Duration = .seconds(600)

    private lazy var pipeline = DictationPipeline(
        cleanUp: { text, instructions, language in
            try await GrammarCorrectionService.shared.correctGrammar(text, instructions: instructions, language: language)
        },
        isDictionaryWord: { [weak self] word in
            DictionaryWords.isWord(word, language: self?.sessionContext?.language)
        }
    )

    private static func boolDefault(_ key: String, _ fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil ? fallback : UserDefaults.standard.bool(forKey: key)
    }

    private func setupHotkey() {
        // Key down: start recording and streaming transcription
        HotkeyService.shared.onKeyDown = { [weak self] in
            print("Hotkey pressed - starting recording")
            self?.handleHotkeyDown()
        }

        // Key up: stop recording and finalize
        HotkeyService.shared.onKeyUp = { [weak self] in
            print("Hotkey released - stopping recording")
            self?.handleHotkeyUp()
        }

        HotkeyService.shared.setup()
        print("Hotkey service setup complete (hold-to-record mode)")
    }

    @MainActor
    private func handleHotkeyDown() {
        switch sessionState {
        case .idle:
            sessionTrigger = RecordingTrigger.stored(UserDefaults.standard.string(forKey: AppSettings.recordingTriggerKey))
            startRecording()
        case .recording where sessionTrigger == .pressToToggle:
            print("Press-to-toggle: stopping")
            Task { await stopRecordingAndFinalize() }
        default:
            print("Not idle (state: \(sessionState)), ignoring key down")
        }
    }

    @MainActor
    private func handleHotkeyUp() {
        guard sessionState == .recording, sessionTrigger == .hold else {
            print("Key up ignored (state: \(sessionState), trigger: \(sessionTrigger))")
            return
        }
        Task { await stopRecordingAndFinalize() }
    }

    @MainActor
    private func startRecording() {
        // Check if model is loaded
        guard TranscriptionService.shared.isModelLoaded else {
            OverlayManager.shared.showError(message: "No model loaded. Please download and select a model in Settings.")
            return
        }

        // Check microphone permission
        PermissionsService.shared.checkMicrophonePermission()
        print("startRecording - microphoneStatus: \(PermissionsService.shared.microphoneStatus)")

        switch PermissionsService.shared.microphoneStatus {
        case .granted:
            beginRecording()
        case .notDetermined, .denied, .unknown:
            // For any non-granted status, request permission first
            // This ensures the app appears in System Settings and shows the dialog if needed
            Task { @MainActor in
                // Bring app to foreground - permission dialogs require this
                NSApp.activate(ignoringOtherApps: true)

                print("About to request microphone permission...")
                let granted = await PermissionsService.shared.requestMicrophonePermission()
                print("Permission request completed, granted: \(granted)")

                if granted {
                    beginRecording()
                } else {
                    // Permission denied - show error and open settings
                    OverlayManager.shared.showError(message: "Microphone access required. Please enable it in System Settings.")
                    // Small delay to let the error show before opening settings
                    try? await Task.sleep(for: .milliseconds(500))
                    PermissionsService.shared.openMicrophoneSettings()
                }
            }
        }
    }

    @MainActor
    private func beginRecording() {
        sessionState = .recording
        sessionStartedAt = Date()

        // Select microphone based on saved priority, skipping any the user has blocked
        let priority = UserDefaults.standard.stringArray(forKey: AppSettings.microphonePriorityKey) ?? []
        let banned = UserDefaults.standard.stringArray(forKey: AppSettings.bannedMicrophoneIDsKey) ?? []
        AudioCaptureService.shared.selectDeviceByPriority(priority, excluding: banned)

        // Start audio capture BEFORE showing UI so no audio is lost
        AudioCaptureService.shared.startRecording()

        // Reset typed text tracking
        typedTextLength = 0
        insertionMode = TextInsertionMode.stored(UserDefaults.standard.string(forKey: AppSettings.textInsertionModeKey))
        stoppedBySafety = false

        // The app in front decides the mode; everything is read now and kept for the session.
        let frontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let mode = ModeStore.shared.mode(forApp: frontApp)
        sessionContext = DictationContext(
            voiceCommands: Self.boolDefault(AppSettings.voiceCommandsEnabledKey, true),
            spokenPunctuation: UserDefaults.standard.bool(forKey: AppSettings.spokenPunctuationEnabledKey),
            pressToToggle: sessionTrigger == .pressToToggle,
            vocabulary: VocabularyStore.shared.entries,
            mode: mode,
            cleanUpEnabled: UserDefaults.standard.bool(forKey: AppSettings.grammarCorrectionEnabledKey),
            language: UserDefaults.standard.string(forKey: AppSettings.selectedLanguageKey))
        TranscriptionService.shared.vocabularyPromptText = VocabularyPrompt.text(VocabularyStore.shared.entries)

        var hint: [String] = []
        if sessionTrigger == .pressToToggle { hint.append("Press the shortcut to stop") }
        if !mode.isDefault { hint.append(mode.name) }
        OverlayManager.shared.listeningHint = hint.isEmpty ? nil : hint.joined(separator: " · ")
        OverlayManager.shared.onTap = sessionTrigger == .pressToToggle ? { [weak self] in self?.handleHotkeyDown() } : nil

        // Show overlay only once we're actually recording
        OverlayManager.shared.showListening()

        safetyStopTask?.cancel()
        if sessionTrigger == .pressToToggle {
            safetyStopTask = Task { [weak self] in
                try? await Task.sleep(for: Self.safetyStop)
                guard !Task.isCancelled, let self, self.sessionState == .recording else { return }
                print("Safety stop after 10 minutes")
                self.stoppedBySafety = true
                // Finalise outside this task's cancellation: the stop cancels `safetyStopTask`, and a
                // cancelled task would cut the final pass short.
                self.safetyStopTask = nil
                await self.stopRecordingAndFinalize()
            }
        }

        // Get language setting
        let language = UserDefaults.standard.string(forKey: AppSettings.selectedLanguageKey)

        // Set up streaming transcription callback to type text as it's recognized. In paste mode
        // nothing is typed until the end; streaming still runs because its text is the fallback
        // when the final pass times out.
        TranscriptionService.shared.onTranscriptionUpdate = { [weak self] text in
            guard let self else { return }
            // Only a session-ending command is acted on live; everything else waits for the final text.
            if let context = self.sessionContext, self.sessionState == .recording,
               DictationPipeline.terminatingCommand(in: text, context: context) != nil {
                print("Spoken session command heard; stopping")
                Task { await self.stopRecordingAndFinalize() }
                return
            }
            guard self.insertionMode.insertsWhileSpeaking else { return }
            print("onTranscriptionUpdate called with: '\(text)'")
            print("Previously typed length: \(self.typedTextLength)")
            // Type only the new text (delta)
            let newLength = ClipboardService.shared.typeNewText(
                fullText: text,
                previouslyTypedLength: self.typedTextLength
            )
            print("New typed length: \(newLength)")
            self.typedTextLength = newLength
        }

        // Start streaming transcription
        print("Starting streaming transcription...")
        TranscriptionService.shared.startStreamingTranscription(language: language, chunkInterval: 2.0)
    }

    @MainActor
    private func stopRecordingAndFinalize() async {
        print("stopRecordingAndFinalize called")
        // Several stop requests can be queued (key, overlay click, spoken command, safety stop); only the first runs.
        guard sessionState == .recording else {
            print("stopRecordingAndFinalize: not recording (state: \(sessionState)), ignoring")
            return
        }
        sessionState = .finalizing

        // Diagnostics: every way this function can end records what the session saw, so a user
        // can copy the report from Settings when a dictation goes wrong.
        var diagnostic = SessionDiagnostic(
            startedAt: sessionStartedAt, trigger: sessionTrigger.rawValue, insertionMode: insertionMode.rawValue,
            modelID: TranscriptionService.shared.loadedModelID ?? "none",
            microphone: AudioCaptureService.shared.selectedDevice?.name ?? "none",
            inputSampleRate: AudioCaptureService.shared.inputSampleRate, channels: AudioCaptureService.shared.inputChannels,
            samples: 0, rms: 0, streamedCharacters: 0, finalCharacters: 0, finalPassMilliseconds: 0,
            insertedCharacters: 0, outcome: "")
        var outcome = "Done"
        defer { diagnostic.outcome = outcome; DiagnosticsLog.shared.record(diagnostic) }
        safetyStopTask?.cancel()
        safetyStopTask = nil
        OverlayManager.shared.onTap = nil

        // Stop streaming transcription and get final text
        let streamedText = TranscriptionService.shared.stopStreamingTranscription()
        diagnostic.streamedCharacters = streamedText.count
        TranscriptionService.shared.onTranscriptionUpdate = nil

        // Stop audio capture
        AudioCaptureService.shared.stopRecording()

        // Short-recording guard: skip transcription if < 0.3s
        if AudioCaptureService.shared.recordingDuration < 0.3 {
            print("Recording too short (\(AudioCaptureService.shared.recordingDuration)s), skipping transcription")
            outcome = "Recording too short"
            OverlayManager.shared.showError(message: "Recording too short")
            AudioCaptureService.shared.clearBuffer()
            typedTextLength = 0
            sessionState = .idle
            return
        }

        // Get audio buffer for final transcription
        let audioBuffer = AudioCaptureService.shared.getAudioBuffer()
        diagnostic.samples = audioBuffer.count
        diagnostic.rms = SessionDiagnostic.rms(audioBuffer)
        let finalPassStarted = ContinuousClock.now
        print("Audio buffer size: \(audioBuffer.count) samples (\(Double(audioBuffer.count) / 16000.0) seconds at 16kHz)")

        var finalTranscription = streamedText

        // If we have audio, do a final transcription for accuracy
        if !audioBuffer.isEmpty {
            // Show processing state briefly
            OverlayManager.shared.showProcessing()

            do {
                let language = UserDefaults.standard.string(forKey: AppSettings.selectedLanguageKey)

                // Add timeout to prevent getting stuck
                let fullTranscription = try await withThrowingTaskGroup(of: String.self) { group in
                    group.addTask {
                        try await TranscriptionService.shared.processAudioBuffer(
                            audioBuffer,
                            language: language
                        )
                    }

                    group.addTask {
                        try await Task.sleep(for: .seconds(30))
                        throw TranscriptionTimeoutError()
                    }

                    let result = try await group.next()!
                    group.cancelAll()
                    return result
                }

                // If final transcription is different/longer, type the difference
                if insertionMode.insertsWhileSpeaking && fullTranscription.count > typedTextLength {
                    let newText = String(fullTranscription.dropFirst(typedTextLength))
                    if !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ClipboardService.shared.typeText(newText)
                        // What is on screen is now the whole final pass.
                        typedTextLength = fullTranscription.count
                    }
                }

                // A blank final pass must not throw away text that streaming already recognised.
                diagnostic.finalCharacters = fullTranscription.count
                diagnostic.finalPassMilliseconds = Int((ContinuousClock.now - finalPassStarted) / .milliseconds(1))
                finalTranscription = fullTranscription.isEmpty ? streamedText : fullTranscription
                print("Final transcription: \(finalTranscription)")
            } catch is TranscriptionTimeoutError {
                print("Final transcription timed out")
                if finalTranscription.isEmpty {
                    outcome = "Processing took too long"
                    OverlayManager.shared.showError(message: "Processing took too long")
                    AudioCaptureService.shared.clearBuffer()
                    typedTextLength = 0
                    sessionState = .idle
                    return
                }
            } catch {
                print("Final transcription error: \(error)")
                // Show error and return early if transcription failed and we have no streamed text
                if finalTranscription.isEmpty {
                    outcome = "Transcription failed"
                    OverlayManager.shared.showError(message: "Transcription failed")
                    AudioCaptureService.shared.clearBuffer()
                    typedTextLength = 0
                    sessionState = .idle
                    return
                }
                // Otherwise continue with streamed text
            }
        } else if finalTranscription.isEmpty {
            // No audio recorded at all
            outcome = "No audio recorded"
            OverlayManager.shared.showError(message: "No audio recorded")
            typedTextLength = 0
            sessionState = .idle
            return
        }

        // Commands, vocabulary and clean-up, with the mode the app in front chose at key down.
        var actions: [DictationAction] = []
        if let context = sessionContext, !finalTranscription.isEmpty {
            let needsModel = context.cleanUpEnabled && context.mode.cleanUp && GrammarCorrectionService.shared.isModelLoaded
            if needsModel { OverlayManager.shared.showProcessing() }
            var effective = context
            effective.cleanUpEnabled = needsModel
            let result = await pipeline.process(finalTranscription, context: effective)
            actions = result.actions
            if result.text != finalTranscription {
                // Type mode: `typedTextLength` is what is on screen, which may differ from the final text.
                if insertionMode.insertsWhileSpeaking {
                    if result.text.isEmpty {
                        ClipboardService.shared.deleteTypedText(characterCount: typedTextLength)
                    } else {
                        ClipboardService.shared.replaceTypedText(characterCount: typedTextLength, withText: result.text)
                    }
                    typedTextLength = result.text.count
                }
                finalTranscription = result.text
            }
        }

        // Copy final transcription to clipboard if enabled
        let copyToClipboard = UserDefaults.standard.object(forKey: AppSettings.copyToClipboardKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: AppSettings.copyToClipboardKey)

        // Paste mode: the finished text goes in once, now. Without the Accessibility permission
        // (lost whenever the app's signature changes) posted keystrokes vanish silently, so the
        // text is copied instead and the user is told why.
        var insertionBlocked = false
        switch TextInsertion.finalAction(mode: insertionMode, text: finalTranscription, copyToClipboard: copyToClipboard,
                                         canInsert: AXIsProcessTrusted()) {
        case .paste(let text, let restoreClipboard):
            // One paste after the whole pipeline; give slow apps half a second to read it before any restore.
            ClipboardService.shared.paste(text, restorePrevious: restoreClipboard, restoreDelay: 0.5)
        case .copyOnly(let text):
            insertionBlocked = true
            ClipboardService.shared.copyToClipboard(text)
            if !didAskForAccessibility {
                didAskForAccessibility = true
                PermissionsService.shared.requestAccessibilityPermission()
            }
        case .nothing:
            break
        }

        if actions.contains(.pressReturn), !finalTranscription.isEmpty {
            // The pasted text must land before Return does.
            try? await Task.sleep(for: .milliseconds(150))
            ClipboardService.shared.pressReturn()
        }

        diagnostic.insertedCharacters = finalTranscription.count
        let didCopyToClipboard = copyToClipboard && !finalTranscription.isEmpty
        if didCopyToClipboard && !TextInsertion.leavesTextOnClipboard(mode: insertionMode, copyToClipboard: copyToClipboard) {
            ClipboardService.shared.copyToClipboard(finalTranscription)
            print("Copied to clipboard: \(finalTranscription)")
        }

        // Show completed state
        if insertionBlocked {
            outcome = "Copied — Accessibility permission missing"
            OverlayManager.shared.showError(message: "Allow Accessibility to insert text — copied to clipboard instead")
        } else if !finalTranscription.isEmpty {
            if stoppedBySafety {
                outcome = "Stopped after 10 minutes"
                OverlayManager.shared.showError(message: "Stopped after 10 minutes")
            } else {
                OverlayManager.shared.showCompleted(copiedToClipboard: didCopyToClipboard)
            }
        } else {
            outcome = "No speech detected"
            OverlayManager.shared.showError(message: "No speech detected")
        }

        // History, when the user turned it on: the final text, and the recording if asked.
        let keep = HistoryPolicy.shouldKeep(
            text: finalTranscription,
            keepTranscriptions: UserDefaults.standard.bool(forKey: AppSettings.historyKeepsTranscriptionsKey),
            keepAudio: UserDefaults.standard.bool(forKey: AppSettings.historyKeepsAudioKey))
        if keep.text {
            // The 16 kHz copy read above for the final pass, taken before clearBuffer() below.
            let audio = keep.audio ? audioBuffer : nil
            let duration = AudioCaptureService.shared.recordingDuration
            let modelID = TranscriptionService.shared.loadedModelID ?? ""
            let language = UserDefaults.standard.string(forKey: AppSettings.selectedLanguageKey)
            let text = finalTranscription
            // The session ends now; the store encodes and writes on its own time.
            Task { await HistoryStore.shared.add(text: text, durationSeconds: duration, modelID: modelID, language: language, audio: audio) }
        }

        // Clear audio buffer
        AudioCaptureService.shared.clearBuffer()

        // Reset typed text tracking
        typedTextLength = 0
        stoppedBySafety = false
        sessionContext = nil
        sessionState = .idle
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "JustScribe")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Start Transcription", action: #selector(startTranscriptionFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Transcribe File…", action: #selector(transcribeFileFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "History…", action: #selector(showHistoryFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdatesFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit JustScribe", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc private func startTranscriptionFromMenu() {
        Task { @MainActor in
            // Menu click toggles recording (unlike hold-to-record with shortcut)
            if sessionState == .recording {
                await stopRecordingAndFinalize()
            } else if sessionState == .idle {
                handleHotkeyDown()
            }
        }
    }

    @objc private func transcribeFileFromMenu() {
        fileTranscription.show()
    }

    @objc private func showHistoryFromMenu() {
        history.show()
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)

        // Find and activate the settings window
        for window in NSApp.windows where window.identifier != FileTranscriptionWindowController.windowIdentifier
            && window.identifier != HistoryWindowController.windowIdentifier {
            if window.identifier?.rawValue.contains("settings") == true ||
               window.title.contains("JustScribe") ||
               window.contentView != nil {
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(window.contentView)
                break
            }
        }
    }

    @objc private func checkForUpdatesFromMenu() {
        // A menu-bar app is usually not frontmost; Sparkle's window must not open behind others.
        NSApp.activate(ignoringOtherApps: true)
        UpdateService.shared.checkForUpdates()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Dock Visibility

    func updateDockVisibility(showInDock: Bool) {
        if showInDock {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Status Bar Visibility

    func updateStatusBarVisibility(showInStatusBar: Bool) {
        if showInStatusBar {
            if statusItem == nil {
                setupStatusBar()
            }
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
        }
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdatesFromMenu) {
            return UpdateService.shared.canCheckForUpdates
        }
        return true
    }
}

extension AppDelegate: DictationActivity {
    /// A dictation session, from key down until the final text has been typed.
    var isDictating: Bool { sessionState != .idle }
}
