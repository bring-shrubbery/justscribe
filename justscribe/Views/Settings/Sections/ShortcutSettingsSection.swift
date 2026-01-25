//
//  ShortcutSettingsSection.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import SwiftUI

struct ShortcutSettingsSection: View {
    @Bindable var settings: AppSettings
    @State private var isRecording = false
    @State private var currentShortcut: String = "Not set"

    var body: some View {
        SettingsSectionContainer(title: "Global Shortcut") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Press a key combination to activate transcription from anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    ShortcutRecorderView(
                        isRecording: $isRecording,
                        currentShortcut: $currentShortcut,
                        onShortcutRecorded: { keyCode, modifiers in
                            settings.shortcutKeyCode = keyCode
                            settings.shortcutModifiers = modifiers
                            updateShortcutDisplay()
                        }
                    )

                    if settings.shortcutKeyCode != 0 {
                        Button("Clear") {
                            settings.shortcutKeyCode = 0
                            settings.shortcutModifiers = 0
                            currentShortcut = "Not set"
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear {
            updateShortcutDisplay()
        }
    }

    private func updateShortcutDisplay() {
        guard settings.shortcutKeyCode != 0 else {
            currentShortcut = "Not set"
            return
        }

        var parts: [String] = []

        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(settings.shortcutModifiers))

        if modifiers.contains(.control) {
            parts.append("^")
        }
        if modifiers.contains(.option) {
            parts.append("\u{2325}")
        }
        if modifiers.contains(.shift) {
            parts.append("\u{21E7}")
        }
        if modifiers.contains(.command) {
            parts.append("\u{2318}")
        }

        if let keyString = keyCodeToString(settings.shortcutKeyCode) {
            parts.append(keyString)
        }

        currentShortcut = parts.joined()
    }

    private func keyCodeToString(_ keyCode: UInt16) -> String? {
        let keyCodeMap: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
            50: "`", 51: "Delete", 53: "Escape",
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
            103: "F11", 105: "F13", 107: "F14", 109: "F10", 111: "F12",
            113: "F15", 118: "F4", 119: "F2", 120: "F1", 122: "F16",
            123: "Left", 124: "Right", 125: "Down", 126: "Up"
        ]
        return keyCodeMap[keyCode]
    }
}

struct ShortcutRecorderView: View {
    @Binding var isRecording: Bool
    @Binding var currentShortcut: String
    var onShortcutRecorded: (UInt16, UInt) -> Void

    var body: some View {
        Button {
            isRecording.toggle()
        } label: {
            HStack(spacing: 8) {
                if isRecording {
                    Image(systemName: "keyboard")
                        .foregroundStyle(Color.accentColor)
                    Text("Press shortcut...")
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text(currentShortcut)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .frame(minWidth: 120)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        // Note: Actual shortcut recording will be implemented with KeyboardShortcuts library
        // This is a placeholder UI that shows the current shortcut
    }
}
