//
//  ShortcutSettingsSection.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import SwiftUI
import KeyboardShortcuts

struct ShortcutSettingsSection: View {
    @State private var currentShortcut: KeyboardShortcuts.Shortcut?

    var body: some View {
        SettingsSectionContainer(title: "Global Shortcut") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Press a key combination to activate transcription from anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    // Use the simpler string-based initializer
                    KeyboardShortcuts.Recorder("Shortcut:", name: .activateTranscription) { newShortcut in
                        currentShortcut = newShortcut
                        print("Shortcut changed to: \(String(describing: newShortcut))")
                    }

                    Button("Reset") {
                        KeyboardShortcuts.reset(.activateTranscription)
                        KeyboardShortcuts.setShortcut(
                            .init(.space, modifiers: [.control, .shift]),
                            for: .activateTranscription
                        )
                        currentShortcut = KeyboardShortcuts.getShortcut(for: .activateTranscription)
                    }
                    .buttonStyle(.bordered)
                }

                if let shortcut = currentShortcut {
                    Text("Current: \(shortcut.description)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No shortcut set. Click the recorder and press a key combination.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                Text("Default: \u{2303}\u{21E7}Space (Control + Shift + Space)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .onAppear {
                currentShortcut = KeyboardShortcuts.getShortcut(for: .activateTranscription)
            }
        }
    }
}
