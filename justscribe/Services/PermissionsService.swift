//
//  PermissionsService.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import Foundation
import AVFoundation
import AppKit

@Observable
final class PermissionsService {
    static let shared = PermissionsService()

    private(set) var microphoneStatus: PermissionStatus = .unknown
    private(set) var inputMonitoringStatus: PermissionStatus = .unknown

    enum PermissionStatus {
        case unknown
        case notDetermined
        case denied
        case granted
    }

    private init() {
        checkPermissions()
    }

    func checkPermissions() {
        checkMicrophonePermission()
        checkInputMonitoringPermission()
    }

    // MARK: - Microphone

    func checkMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            microphoneStatus = .notDetermined
        case .restricted, .denied:
            microphoneStatus = .denied
        case .authorized:
            microphoneStatus = .granted
        @unknown default:
            microphoneStatus = .unknown
        }
    }

    func requestMicrophonePermission() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        await MainActor.run {
            microphoneStatus = granted ? .granted : .denied
        }
        return granted
    }

    // MARK: - Input Monitoring (for global hotkeys)

    func checkInputMonitoringPermission() {
        // CGPreflightListenEventAccess() checks if the app has input monitoring permission
        // This is needed for global keyboard shortcuts
        let hasAccess = CGPreflightListenEventAccess()
        inputMonitoringStatus = hasAccess ? .granted : .notDetermined
    }

    func requestInputMonitoringPermission() {
        // Request permission - this will show the system dialog
        let hasAccess = CGRequestListenEventAccess()
        inputMonitoringStatus = hasAccess ? .granted : .denied

        if !hasAccess {
            // Open System Settings to the Privacy > Input Monitoring pane
            openInputMonitoringSettings()
        }
    }

    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
