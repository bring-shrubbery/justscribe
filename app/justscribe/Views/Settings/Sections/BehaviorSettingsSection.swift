//
//  BehaviorSettingsSection.swift
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
import LaunchAtLogin

extension Notification.Name {
    static let updateStatusBarVisibility = Notification.Name("updateStatusBarVisibility")
}

struct BehaviorSettingsSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsSectionContainer(title: "Behavior") {
            VStack(spacing: 12) {
                // Launch at Login using LaunchAtLogin library
                HStack(spacing: 12) {
                    Image(systemName: "power")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at Login")
                            .font(.body)
                        Text("Start JustScribe when you log in")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    LaunchAtLogin.Toggle {
                        EmptyView()
                    }
                    .toggleStyle(.pill)
                    .labelsHidden()
                }

                Divider()

                ToggleSettingsRow(
                    title: "Show in Dock",
                    subtitle: "Display app icon in the Dock",
                    systemImage: "dock.rectangle",
                    isOn: Binding(
                        get: { settings.showInDock },
                        set: { newValue in
                            settings.showInDock = newValue
                            UserDefaults.standard.set(newValue, forKey: AppSettings.showInDockKey)
                            updateDockVisibility(newValue)
                        }
                    )
                )

                Divider()

                ToggleSettingsRow(
                    title: "Show in Menu Bar",
                    subtitle: "Display icon in the menu bar",
                    systemImage: "menubar.rectangle",
                    isOn: Binding(
                        get: { settings.showInStatusBar },
                        set: { newValue in
                            settings.showInStatusBar = newValue
                            UserDefaults.standard.set(newValue, forKey: AppSettings.showInStatusBarKey)
                            updateStatusBarVisibility(newValue)
                        }
                    )
                )

                Divider()

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

                Divider()

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
        }
    }

    private func updateDockVisibility(_ show: Bool) {
        if show {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func updateStatusBarVisibility(_ show: Bool) {
        NotificationCenter.default.post(
            name: .updateStatusBarVisibility,
            object: nil,
            userInfo: ["show": show]
        )
    }
}

struct ToggleSettingsRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.pill)
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
