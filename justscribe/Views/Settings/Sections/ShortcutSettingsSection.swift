//
//  ShortcutSettingsSection.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import SwiftUI
import KeyboardShortcuts

struct ShortcutSettingsSection: View {
    var body: some View {
        SettingsSectionContainer(title: "Global Shortcut") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Press a key combination to activate transcription from anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    KeyboardShortcuts.Recorder(for: .activateTranscription) {
                        Text("Shortcut:")
                    }

                    Button("Set Default") {
                        KeyboardShortcuts.setShortcut(
                            .init(.space, modifiers: [.control, .shift]),
                            for: .activateTranscription
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Text("Default: \u{2303}\u{21E7}Space (Control + Shift + Space)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
