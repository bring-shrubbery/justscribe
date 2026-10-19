//
//  StartupSettingsSection.swift
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
import LaunchAtLogin

extension Notification.Name {
    static let updateStatusBarVisibility = Notification.Name("updateStatusBarVisibility")
}

/// How the app starts and where it shows: login item, Dock, menu bar.
struct StartupSettingsSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsSectionContainer(title: "Startup") {
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
