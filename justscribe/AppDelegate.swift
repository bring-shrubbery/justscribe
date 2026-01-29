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

    func applicationDidFinishLaunching(_ notification: Notification) {
        applySavedVisibilitySettings()
        checkInputMonitoringAndSetupHotkey()
        loadSelectedModel()
        setupNotificationObservers()
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Unload the model to free memory
        // This is called on the main thread by AppKit, so we can safely access MainActor-isolated code
        MainActor.assumeIsolated {
            TranscriptionService.shared.unloadModel()
            print("Model unloaded on app termination")
        }
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
    }

    @MainActor
    private func stopRecordingAndFinalize() async {
        print("stopRecordingAndFinalize called")

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

        let didCopyToClipboard = copyToClipboard && !finalTranscription.isEmpty
        if didCopyToClipboard {
            ClipboardService.shared.copyToClipboard(finalTranscription)
            print("Copied to clipboard: \(finalTranscription)")
        }

        // Show completed state
        if !finalTranscription.isEmpty {
            OverlayManager.shared.showCompleted(copiedToClipboard: didCopyToClipboard)
        } else {
            OverlayManager.shared.showError(message: "No speech detected")
        }

        // Clear audio buffer
        AudioCaptureService.shared.clearBuffer()

        // Reset typed text tracking
        typedTextLength = 0
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
