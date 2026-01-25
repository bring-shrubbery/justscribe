//
//  BehaviorSettingsSection.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import SwiftUI

struct BehaviorSettingsSection: View {
    @Bindable var settings: AppSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        SettingsSectionContainer(title: "Behavior") {
            VStack(spacing: 12) {
                ToggleSettingsRow(
                    title: "Launch at Login",
                    subtitle: "Start JustScribe when you log in",
                    systemImage: "power",
                    isOn: $settings.launchAtLogin
                )
                .onChange(of: settings.launchAtLogin) { _, newValue in
                    updateLaunchAtLogin(newValue)
                }

                Divider()

                ToggleSettingsRow(
                    title: "Show in Dock",
                    subtitle: "Display app icon in the Dock",
                    systemImage: "dock.rectangle",
                    isOn: $settings.showInDock
                )
                .onChange(of: settings.showInDock) { _, newValue in
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
                    updateStatusBarVisibility(newValue)
                }

                Divider()

                ToggleSettingsRow(
                    title: "Escape to Cancel",
                    subtitle: "Press Escape to cancel recording",
                    systemImage: "escape",
                    isOn: $settings.escapeToCancel
                )

                Divider()

                ToggleSettingsRow(
                    title: "Copy to Clipboard",
                    subtitle: "Automatically copy transcription result",
                    systemImage: "doc.on.clipboard",
                    isOn: $settings.copyToClipboard
                )
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        // Will be implemented with LaunchAtLogin library
        // LaunchAtLogin.isEnabled = enabled
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
