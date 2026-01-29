//
//  BehaviorSettingsSection.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import SwiftUI
import LaunchAtLogin

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
                    isOn: $settings.showInDock
                )
                .onChange(of: settings.showInDock) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: AppSettings.showInDockKey)
                    updateDockVisibility(newValue)
                }

                Divider()

                ToggleSettingsRow(
                    title: "Show in Menu Bar",
                    subtitle: "Display icon in the menu bar",
                    systemImage: "menubar.rectangle",
                    isOn: $settings.showInStatusBar
                )
                .onChange(of: settings.showInStatusBar) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: AppSettings.showInStatusBarKey)
                    updateStatusBarVisibility(newValue)
                }

                Divider()

                ToggleSettingsRow(
                    title: "Escape to Cancel",
                    subtitle: "Press Escape to cancel recording",
                    systemImage: "escape",
                    isOn: $settings.escapeToCancel
                )
                .onChange(of: settings.escapeToCancel) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: AppSettings.escapeToCancelKey)
                }

                Divider()

                ToggleSettingsRow(
                    title: "Copy to Clipboard",
                    subtitle: "Automatically copy transcription result",
                    systemImage: "doc.on.clipboard",
                    isOn: $settings.copyToClipboard
                )
                .onChange(of: settings.copyToClipboard) { _, newValue in
                    print("Copy to Clipboard changed to: \(newValue)")
                    UserDefaults.standard.set(newValue, forKey: AppSettings.copyToClipboardKey)
                    print("UserDefaults now has: \(UserDefaults.standard.bool(forKey: AppSettings.copyToClipboardKey))")
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func updateDockVisibility(_ show: Bool) {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.updateDockVisibility(showInDock: show)
        }
    }

    private func updateStatusBarVisibility(_ show: Bool) {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.updateStatusBarVisibility(showInStatusBar: show)
        }
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
