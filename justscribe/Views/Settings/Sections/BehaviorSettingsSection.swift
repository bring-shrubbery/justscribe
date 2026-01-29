//
//  BehaviorSettingsSection.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
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
                    .toggleStyle(.switch)
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

                ToggleSettingsRow(
                    title: "Copy to Clipboard",
                    subtitle: "Automatically copy transcription result",
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
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
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
                .toggleStyle(.switch)
        }
    }
}
