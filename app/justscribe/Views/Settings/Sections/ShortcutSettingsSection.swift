//
//  ShortcutSettingsSection.swift
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

import SwiftUI
import KeyboardShortcuts

struct ShortcutSettingsSection: View {
    @Bindable var settings: AppSettings
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

                Divider()

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "record.circle")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recording")
                            .font(.body)
                        Picker("", selection: Binding(
                            get: { settings.recordingTrigger },
                            set: { settings.recordingTrigger = $0 }
                        )) {
                            ForEach(RecordingTrigger.allCases, id: \.self) { trigger in
                                Text(trigger.title).tag(trigger)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.radioGroup)
                        Text(settings.recordingTrigger.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("Default: \u{2303}\u{21E7}Space (Control + Shift + Space)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Text("Tip: Modifier-only shortcuts like Control + Shift work too.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .onAppear {
                shortcutConfig = ShortcutConfig.load() ?? ShortcutConfig.defaultConfig
            }
        }
    }
}
