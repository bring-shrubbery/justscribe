//
//  PermissionsSettingsSection.swift
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
import AppKit
import SwiftUI

/// The three macOS permissions dictation needs, with their current state and a way to fix each.
/// Re-checked whenever the app comes to the front, since they are changed in System Settings.
struct PermissionsSettingsSection: View {
    private var permissions: PermissionsService { .shared }
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        SettingsSectionContainer(title: "Permissions") {
            VStack(spacing: 12) {
                PermissionRow(
                    title: "Microphone",
                    detail: "Records your voice.",
                    status: permissions.microphoneStatus,
                    fix: { permissions.openMicrophoneSettings() }
                )
                Divider()
                PermissionRow(
                    title: "Accessibility",
                    detail: "Inserts the text into the app you are dictating into. Without it, dictations are only copied to the clipboard. macOS forgets this permission when the app is updated with a new signature; switch it off and on again if it looks granted but text does not appear.",
                    status: permissions.accessibilityStatus,
                    fix: {
                        permissions.requestAccessibilityPermission()
                        permissions.openAccessibilitySettings()
                    }
                )
                Divider()
                PermissionRow(
                    title: "Input Monitoring",
                    detail: "Lets the shortcut work while other apps are in front.",
                    status: permissions.inputMonitoringStatus,
                    fix: { permissions.openInputMonitoringSettings() }
                )
            }
        }
        .onAppear { permissions.checkPermissions(); startRefreshing() }
        .onDisappear { refreshTask?.cancel(); refreshTask = nil }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.checkPermissions()
        }
    }

    /// System Settings changes nothing in-process, so poll gently while this section is visible.
    private func startRefreshing() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                permissions.checkPermissions()
            }
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let status: PermissionsService.PermissionStatus
    let fix: () -> Void

    private var isGranted: Bool { status == .granted }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.body)
                .foregroundStyle(isGranted ? Color.green : Color.orange)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.body)
                    Text(isGranted ? "Allowed" : "Not allowed")
                        .font(.caption)
                        .foregroundStyle(isGranted ? Color.secondary : Color.orange)
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !isGranted {
                Button("Open System Settings…", action: fix)
                    .buttonStyle(.pill)
            }
        }
    }
}
