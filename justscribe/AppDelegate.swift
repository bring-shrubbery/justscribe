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

    private func setupHotkey() {
        HotkeyService.shared.onActivate = { [weak self] in
            print("Hotkey activated!")
            self?.handleHotkeyActivation()
        }
        HotkeyService.shared.setup()
        print("Hotkey service setup complete")
    }

    @MainActor
    private func handleHotkeyActivation() {
        // Check if already recording
        if OverlayManager.shared.isVisible {
            // Stop recording and process
            Task {
                await stopRecordingAndTranscribe()
            }
        } else {
            // Start recording
            startRecording()
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

        switch PermissionsService.shared.microphoneStatus {
        case .granted:
            beginRecording()
        case .notDetermined:
            // Request permission
            Task {
                let granted = await PermissionsService.shared.requestMicrophonePermission()
                if granted {
                    beginRecording()
                } else {
                    OverlayManager.shared.showError(message: "Microphone access denied. Enable it in System Settings.")
                }
            }
        case .denied:
            OverlayManager.shared.showError(message: "Microphone access denied. Enable it in System Settings.")
            PermissionsService.shared.openMicrophoneSettings()
        case .unknown:
            OverlayManager.shared.showError(message: "Unable to check microphone permission.")
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

        // Stop audio capture and clear buffer
        AudioCaptureService.shared.stopRecording()
        AudioCaptureService.shared.clearBuffer()

        // Hide overlay
        OverlayManager.shared.hide()
    }

    @MainActor
    private func stopRecordingAndTranscribe() async {
        // Stop escape key monitor
        stopEscapeKeyMonitor()

        // Stop audio capture
        AudioCaptureService.shared.stopRecording()

        // Show processing state
        OverlayManager.shared.showProcessing()

        // Process transcription
        do {
            // Get language setting (nil means auto-detect)
            let language = UserDefaults.standard.string(forKey: AppSettings.selectedLanguageKey)

            let transcription = try await TranscriptionService.shared.processAudioBuffer(
                AudioCaptureService.shared.getAudioBuffer(),
                language: language
            )

            // Copy to clipboard if enabled
            let copyToClipboard = UserDefaults.standard.object(forKey: AppSettings.copyToClipboardKey) == nil
                ? true
                : UserDefaults.standard.bool(forKey: AppSettings.copyToClipboardKey)

            if copyToClipboard {
                ClipboardService.shared.copyToClipboard(transcription)
            }

            // Show completed state
            OverlayManager.shared.showCompleted(text: transcription)

            // Clear audio buffer
            AudioCaptureService.shared.clearBuffer()
        } catch {
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
            handleHotkeyActivation()
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
