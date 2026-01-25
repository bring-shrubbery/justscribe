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
        setupStatusBar()
        setupHotkey()
        loadSelectedModel()
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
                try await TranscriptionService.shared.loadModel(variant: modelID)
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
            self?.handleHotkeyActivation()
        }
        HotkeyService.shared.setup()
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

        // Show overlay in listening state
        OverlayManager.shared.showListening()

        // Start audio capture
        AudioCaptureService.shared.startRecording()
    }

    @MainActor
    private func stopRecordingAndTranscribe() async {
        // Stop audio capture
        AudioCaptureService.shared.stopRecording()

        // Show processing state
        OverlayManager.shared.showProcessing()

        // Process transcription (placeholder - will be implemented with WhisperKit)
        do {
            let transcription = try await TranscriptionService.shared.processAudioBuffer(
                AudioCaptureService.shared.getAudioBuffer()
            )

            // Copy to clipboard if enabled
            // TODO: Check settings for copyToClipboard
            ClipboardService.shared.copyToClipboard(transcription)

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

        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "settings" }) {
            window.makeKeyAndOrderFront(nil)
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
