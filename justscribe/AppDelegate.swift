//
//  AppDelegate.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var escapeKeyMonitor: Any?
    private var localEscapeKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        checkInputMonitoringAndSetupHotkey()
        loadSelectedModel()
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

        // Check if model is downloaded
        let downloadService = ModelDownloadService.shared
        guard downloadService.isModelDownloaded(modelID) else {
            print("Selected model '\(modelID)' is not downloaded, skipping auto-load")
            return
        }

        // Load the model asynchronously
        Task { @MainActor in
            do {
                print("Auto-loading model: \(modelID)")
                try await TranscriptionService.shared.loadModel(unifiedID: modelID)
                print("Model loaded successfully")
            } catch {
                print("Failed to auto-load model: \(error.localizedDescription)")
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Hotkey Setup

    /// Tracks how much text has been typed during streaming (for incremental typing)
    private var typedTextLength = 0

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
        // Only start if not already recording
        guard !OverlayManager.shared.isVisible else {
            print("Already recording, ignoring key down")
            return
        }

        startRecording()
    }

    @MainActor
    private func handleHotkeyUp() {
        // Only stop if currently recording
        guard OverlayManager.shared.isVisible else {
            print("Not recording, ignoring key up")
            return
        }

        Task {
            await stopRecordingAndFinalize()
        }
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
        // Select microphone based on saved priority
        if let priority = UserDefaults.standard.stringArray(forKey: AppSettings.microphonePriorityKey) {
            AudioCaptureService.shared.selectDeviceByPriority(priority)
        }

        // Show overlay in listening state
        OverlayManager.shared.showListening()

        // Start audio capture
        AudioCaptureService.shared.startRecording()

        // Reset typed text tracking
        typedTextLength = 0

        // Get language setting
        let language = UserDefaults.standard.string(forKey: AppSettings.selectedLanguageKey)

        // Set up streaming transcription callback to type text as it's recognized
        TranscriptionService.shared.onTranscriptionUpdate = { [weak self] text in
            guard let self = self else { return }
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

        // Start listening for Escape key to cancel
        startEscapeKeyMonitor()

        // Start listening for Escape key
        startEscapeKeyMonitor()
    }

    // MARK: - Escape to Cancel

    private func startEscapeKeyMonitor() {
        // Remove any existing monitor
        stopEscapeKeyMonitor()

        // Use global monitor so escape works even when app isn't focused
        // Note: This requires Input Monitoring permission
        escapeKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // 53 = Escape key
                Task { @MainActor in
                    self?.handleEscapePressed()
                }
            }
        }

        // Also add local monitor for when app IS focused
        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // 53 = Escape key
                self?.handleEscapePressed()
                return nil // Consume the event
            }
            return event
        }
        // Store as secondary monitor - we'll manage both
        localEscapeKeyMonitor = localMonitor
    }

    private func stopEscapeKeyMonitor() {
        if let monitor = escapeKeyMonitor {
            NSEvent.removeMonitor(monitor)
            escapeKeyMonitor = nil
        }
        if let monitor = localEscapeKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localEscapeKeyMonitor = nil
        }
    }

    @MainActor
    private func handleEscapePressed() {
        // Check if escape-to-cancel is enabled
        let escapeToCancel = UserDefaults.standard.bool(forKey: AppSettings.escapeToCancelKey)

        // Default to true if not set
        let shouldCancel = UserDefaults.standard.object(forKey: AppSettings.escapeToCancelKey) == nil ? true : escapeToCancel

        guard shouldCancel else { return }
        guard OverlayManager.shared.isVisible else { return }

        cancelRecording()
    }

    @MainActor
    private func cancelRecording() {
        // Stop monitoring
        stopEscapeKeyMonitor()

        // Stop streaming transcription
        TranscriptionService.shared.stopStreamingTranscription()
        TranscriptionService.shared.onTranscriptionUpdate = nil

        // Stop audio capture and clear buffer
        AudioCaptureService.shared.stopRecording()
        AudioCaptureService.shared.clearBuffer()

        // Reset typed text tracking
        typedTextLength = 0

        // Hide overlay
        OverlayManager.shared.hide()
    }

    @MainActor
    private func stopRecordingAndFinalize() async {
        print("stopRecordingAndFinalize called")

        // Stop escape key monitor
        stopEscapeKeyMonitor()

        // Stop streaming transcription and get final text
        let streamedText = TranscriptionService.shared.stopStreamingTranscription()
        TranscriptionService.shared.onTranscriptionUpdate = nil

        // Stop audio capture
        AudioCaptureService.shared.stopRecording()

        // Get audio buffer for final transcription
        let audioBuffer = AudioCaptureService.shared.getAudioBuffer()
        print("Audio buffer size: \(audioBuffer.count) samples (\(Double(audioBuffer.count) / 16000.0) seconds at 16kHz)")

        var finalTranscription = streamedText

        // If we have audio, do a final transcription for accuracy
        if !audioBuffer.isEmpty {
            // Show processing state briefly
            OverlayManager.shared.showProcessing()

            do {
                let language = UserDefaults.standard.string(forKey: AppSettings.selectedLanguageKey)
                let fullTranscription = try await TranscriptionService.shared.processAudioBuffer(
                    audioBuffer,
                    language: language
                )

                // If final transcription is different/longer, type the difference
                if fullTranscription.count > typedTextLength {
                    let newText = String(fullTranscription.dropFirst(typedTextLength))
                    if !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ClipboardService.shared.typeText(newText)
                    }
                }

                finalTranscription = fullTranscription
                print("Final transcription: \(finalTranscription)")
            } catch {
                print("Final transcription error: \(error)")
                // Use the streamed text if final transcription fails
            }
        }

        // Copy final transcription to clipboard if enabled
        let copyToClipboard = UserDefaults.standard.object(forKey: AppSettings.copyToClipboardKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: AppSettings.copyToClipboardKey)

        if copyToClipboard && !finalTranscription.isEmpty {
            ClipboardService.shared.copyToClipboard(finalTranscription)
            print("Copied to clipboard: \(finalTranscription)")
        }

        // Show completed state
        if !finalTranscription.isEmpty {
            OverlayManager.shared.showCompleted(text: finalTranscription)
        } else {
            OverlayManager.shared.showError(message: "No speech detected")
        }

        // Clear audio buffer
        AudioCaptureService.shared.clearBuffer()

        // Reset typed text tracking
        typedTextLength = 0
    }

    // Legacy function for backwards compatibility (if needed)
    @MainActor
    private func stopRecordingAndTranscribe() async {
        await stopRecordingAndFinalize()
    }

    // Unused - keeping for reference
    @MainActor
    private func oldStopRecordingAndTranscribe() async {
        print("stopRecordingAndTranscribe called")

        // Stop escape key monitor
        stopEscapeKeyMonitor()

        // Stop audio capture
        AudioCaptureService.shared.stopRecording()

        // Get audio buffer
        let audioBuffer = AudioCaptureService.shared.getAudioBuffer()
        print("Audio buffer size: \(audioBuffer.count) samples (\(Double(audioBuffer.count) / 16000.0) seconds at 16kHz)")

        guard !audioBuffer.isEmpty else {
            print("Audio buffer is empty!")
            OverlayManager.shared.showError(message: "No audio recorded. Please try again.")
            return
        }

        // Show processing state
        OverlayManager.shared.showProcessing()

        // Process transcription
        do {
            // Get language setting (nil means auto-detect)
            let language = UserDefaults.standard.string(forKey: AppSettings.selectedLanguageKey)
            print("Starting transcription with language: \(language ?? "auto")")

            let transcription = try await TranscriptionService.shared.processAudioBuffer(
                audioBuffer,
                language: language
            )
            print("Transcription result: \(transcription)")

            // Copy to clipboard and paste into focused input
            let copyToClipboard = UserDefaults.standard.object(forKey: AppSettings.copyToClipboardKey) == nil
                ? true
                : UserDefaults.standard.bool(forKey: AppSettings.copyToClipboardKey)

            if copyToClipboard {
                ClipboardService.shared.copyAndPaste(transcription)
            }

            // Show completed state
            OverlayManager.shared.showCompleted(text: transcription)

            // Clear audio buffer
            AudioCaptureService.shared.clearBuffer()
        } catch {
            print("Transcription error: \(error)")
            OverlayManager.shared.showError(message: error.localizedDescription)
        }
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "JustScribe")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Start Transcription", action: #selector(startTranscriptionFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit JustScribe", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc private func startTranscriptionFromMenu() {
        Task { @MainActor in
            // Menu click toggles recording (unlike hold-to-record with shortcut)
            if OverlayManager.shared.isVisible {
                await stopRecordingAndFinalize()
            } else {
                handleHotkeyDown()
            }
        }
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)

        // Find and activate the settings window
        for window in NSApp.windows {
            if window.identifier?.rawValue.contains("settings") == true ||
               window.title.contains("JustScribe") ||
               window.contentView != nil {
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(window.contentView)
                break
            }
        }
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
