//
//  ShortcutSettingsSection.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import SwiftUI
import KeyboardShortcuts

struct ShortcutSettingsSection: View {
    @State private var shortcutConfig: ShortcutConfig?

    var body: some View {
        SettingsSectionContainer(title: "Global Shortcut") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Press a key combination to activate transcription from anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Text("Shortcut:")

                    ShortcutRecorderView(config: $shortcutConfig)
                        .onChange(of: shortcutConfig) { _, newValue in
                            if let config = newValue {
                                config.save()
                                // Sync to KeyboardShortcuts library for modifier+key combos
                                if !config.isModifierOnly, let shortcut = config.toKeyboardShortcut() {
                                    KeyboardShortcuts.setShortcut(shortcut, for: .activateTranscription)
                                }
                                HotkeyService.shared.shortcutDidChange()
                                print("Shortcut changed to: \(config.displayString)")
                            }
                        }

                    Button("Reset") {
                        let defaultConfig = ShortcutConfig.defaultConfig
                        defaultConfig.save()
                        shortcutConfig = defaultConfig
                        KeyboardShortcuts.reset(.activateTranscription)
                        if let shortcut = defaultConfig.toKeyboardShortcut() {
                            KeyboardShortcuts.setShortcut(shortcut, for: .activateTranscription)
                        }
                        HotkeyService.shared.shortcutDidChange()
                    }
                    .buttonStyle(.bordered)
                }

                if let config = shortcutConfig {
                    Text("Current: \(config.readableDescription)")
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

                Text("Tip: You can set modifier-only shortcuts like Control + Shift (hold to record, release to stop).")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .onAppear {
                shortcutConfig = ShortcutConfig.load() ?? ShortcutConfig.defaultConfig
            }
        }
    }
}
