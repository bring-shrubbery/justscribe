//
//  UpdateSettingsSection.swift
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

struct UpdateSettingsSection: View {
    private var service: UpdateService { .shared }

    var body: some View {
        SettingsSectionContainer(title: "Updates") {
            VStack(spacing: 12) {
                ToggleSettingsRow(
                    title: "Automatically install updates",
                    subtitle: "New versions download in the background and install when JustScribe quits",
                    systemImage: "arrow.down.circle",
                    isOn: Binding(
                        get: { service.automaticallyInstallsUpdates },
                        set: { service.automaticallyInstallsUpdates = $0 }
                    )
                )

                Divider()

                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Check for Updates")
                            .font(.body)
                        Text("Version \(appVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Check Now") {
                        service.checkForUpdates()
                    }
                    .buttonStyle(.pill)
                    .disabled(!service.canCheckForUpdates)
                }
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
