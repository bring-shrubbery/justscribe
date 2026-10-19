//
//  DictationBehaviorSettingsSection.swift
//  justscribe
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

/// What happens to the words between the shortcut and the target app: how the text is
/// inserted, whether it is copied, and which spoken commands are understood.
struct DictationBehaviorSettingsSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsSectionContainer(title: "Text") {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "text.insert")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Insert Text By")
                        .font(.body)
                    InsertionModePicker(selection: Binding(
                        get: { settings.textInsertionMode },
                        set: { settings.textInsertionMode = $0 }
                    ))
                    Text(settings.textInsertionMode.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            ToggleSettingsRow(
                title: "Copy to Clipboard",
                subtitle: "Keep each transcription on the clipboard afterwards",
                systemImage: "doc.on.clipboard",
                isOn: Binding(
                    get: { settings.copyToClipboard },
                    set: { newValue in
                        settings.copyToClipboard = newValue
                        UserDefaults.standard.set(newValue, forKey: AppSettings.copyToClipboardKey)
                    }
                )
            )
        }

        SettingsSectionContainer(title: "Voice Commands") {
            ToggleSettingsRow(
                title: "Voice Commands",
                subtitle: "Say \"new line\", \"new paragraph\", \"scratch that\", \"stop recording\" or \"send\" while dictating",
                systemImage: "waveform.and.mic",
                isOn: Binding(
                    get: { settings.voiceCommandsEnabled },
                    set: { settings.voiceCommandsEnabled = $0 }
                )
            )

            ToggleSettingsRow(
                title: "Spoken Punctuation",
                subtitle: "Say \"period\", \"comma\", \"question mark\", \"open quote\"… to punctuate",
                systemImage: "textformat.abc.dottedunderline",
                isOn: Binding(
                    get: { settings.spokenPunctuationEnabled },
                    set: { settings.spokenPunctuationEnabled = $0 }
                )
            )
            .disabled(!settings.voiceCommandsEnabled)
            .opacity(settings.voiceCommandsEnabled ? 1 : 0.5)
        }
    }
}

/// Two text segments in the style of the appearance picker.
private struct InsertionModePicker: View {
    @Binding var selection: TextInsertionMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(TextInsertionMode.allCases, id: \.self) { mode in
                let isSelected = selection == mode
                Button {
                    selection = mode
                } label: {
                    Text(mode.displayName)
                        .font(.callout)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                    .shadow(color: .black.opacity(0.08), radius: 1, y: 0.5)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .separatorColor).opacity(0.35))
        )
    }
}
