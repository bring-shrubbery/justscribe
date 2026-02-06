//
//  ShortcutRecorderView.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 06/02/2026.
//

import SwiftUI
import Carbon.HIToolbox

struct ShortcutRecorderView: View {
    @Binding var config: ShortcutConfig?

    @State private var isRecording = false
    @State private var peakModifiers: NSEvent.ModifierFlags = []
    @State private var currentModifiers: NSEvent.ModifierFlags = []
    @State private var keyMonitor: Any?
    @State private var flagsMonitor: Any?

    private let relevantModifiers: NSEvent.ModifierFlags = [.control, .shift, .option, .command]

    var body: some View {
        Button {
            if isRecording {
                cancelRecording()
            } else {
                startRecording()
            }
        } label: {
            HStack(spacing: 4) {
                if isRecording {
                    if currentModifiers.intersection(relevantModifiers).isEmpty {
                        Text("Type shortcut…")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(modifiersDisplayString(currentModifiers))
                            .fontWeight(.medium)
                    }
                } else if let config = config {
                    Text(config.displayString)
                        .fontWeight(.medium)
                } else {
                    Text("Record Shortcut")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 120)
        }
        .buttonStyle(.bordered)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .onDisappear {
            removeMonitors()
        }
    }

    // MARK: - Recording

    private func startRecording() {
        isRecording = true
        peakModifiers = []
        currentModifiers = []

        // Temporarily disable global hotkey to prevent conflicts
        HotkeyService.shared.disable()

        // Monitor key down events
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyDown(event)
            return nil // consume the event
        }

        // Monitor modifier flag changes
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handleFlagsChanged(event)
            return event
        }
    }

    private func cancelRecording() {
        removeMonitors()
        isRecording = false
        peakModifiers = []
        currentModifiers = []

        // Re-enable hotkey
        HotkeyService.shared.setup()
    }

    private func finishRecording(with newConfig: ShortcutConfig) {
        removeMonitors()
        isRecording = false
        peakModifiers = []
        currentModifiers = []
        config = newConfig

        // Re-enable hotkey (setup will be called by the onChange handler in ShortcutSettingsSection)
    }

    private func removeMonitors() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
    }

    // MARK: - Event Handling

    private func handleKeyDown(_ event: NSEvent) {
        // ESC cancels recording
        if event.keyCode == UInt16(kVK_Escape) {
            cancelRecording()
            return
        }

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .intersection(relevantModifiers)

        // Require at least one modifier for modifier+key combos
        guard !mods.isEmpty else { return }

        let newConfig = ShortcutConfig(
            keyCode: Int(event.keyCode),
            modifiers: mods.rawValue
        )
        finishRecording(with: newConfig)
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .intersection(relevantModifiers)

        currentModifiers = mods

        // Track peak modifiers (max set held simultaneously)
        if mods.contains(peakModifiers) {
            // Current is superset of or equal to peak - update peak
            peakModifiers = mods
        }

        // All modifiers released - check if we have a modifier-only shortcut
        if mods.isEmpty && !peakModifiers.isEmpty {
            // Count how many modifiers were held
            var count = 0
            if peakModifiers.contains(.control) { count += 1 }
            if peakModifiers.contains(.shift) { count += 1 }
            if peakModifiers.contains(.option) { count += 1 }
            if peakModifiers.contains(.command) { count += 1 }

            // Require at least 2 modifiers for modifier-only shortcuts
            if count >= 2 {
                let newConfig = ShortcutConfig(
                    keyCode: nil,
                    modifiers: peakModifiers.rawValue
                )
                finishRecording(with: newConfig)
            } else {
                // Reset peak - single modifier tap is not valid
                peakModifiers = []
            }
        }
    }

    // MARK: - Display Helpers

    private func modifiersDisplayString(_ flags: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        return parts.joined()
    }
}
