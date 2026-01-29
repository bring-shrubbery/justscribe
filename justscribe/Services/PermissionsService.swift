//
//  PermissionsService.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import Foundation
import AVFoundation
import AppKit
import CoreAudio

@Observable
final class PermissionsService {
    static let shared = PermissionsService()

    private(set) var microphoneStatus: PermissionStatus = .unknown
    private(set) var inputMonitoringStatus: PermissionStatus = .unknown
    private(set) var accessibilityStatus: PermissionStatus = .unknown

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
        checkAccessibilityPermission()
    }

    // MARK: - Microphone

    func checkMicrophonePermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        print("Microphone authorization status: \(status.rawValue) (\(statusDescription(status)))")

        switch status {
        case .notDetermined:
            microphoneStatus = .notDetermined
        case .restricted:
            print("Microphone access is restricted (parental controls or MDM)")
            microphoneStatus = .denied
        case .denied:
            microphoneStatus = .denied
        case .authorized:
            microphoneStatus = .granted
        @unknown default:
            microphoneStatus = .unknown
        }
    }

    private func statusDescription(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorized: return "authorized"
        @unknown default: return "unknown"
        }
    }

    func requestMicrophonePermission() async -> Bool {
        print("Requesting microphone permission...")

        // First try the standard API
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        print("Current status before request: \(statusDescription(status))")

        if status == .notDetermined {
            // Try to trigger permission by actually accessing a microphone device
            // This can prompt the dialog when requestAccess doesn't
            let granted = await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    // Try to get a microphone device - this can trigger the permission dialog
                    let discoverySession = AVCaptureDevice.DiscoverySession(
                        deviceTypes: [.microphone],
                        mediaType: .audio,
                        position: .unspecified
                    )

                    if let device = discoverySession.devices.first {
                        print("Found microphone device: \(device.localizedName)")
                        // Try to create an input - this should trigger permission dialog
                        do {
                            let input = try AVCaptureDeviceInput(device: device)
                            print("Successfully created input, permission granted")
                            _ = input // Use the input to avoid warning
                            continuation.resume(returning: true)
                        } catch {
                            print("Failed to create input: \(error)")
                            // Fall back to requestAccess
                            Task {
                                let result = await AVCaptureDevice.requestAccess(for: .audio)
                                continuation.resume(returning: result)
                            }
                        }
                    } else {
                        print("No microphone devices found")
                        // Fall back to requestAccess
                        Task {
                            let result = await AVCaptureDevice.requestAccess(for: .audio)
                            continuation.resume(returning: result)
                        }
                    }
                }
            }
            print("Microphone permission result: \(granted)")
            await MainActor.run {
                microphoneStatus = granted ? .granted : .denied
            }
            return granted
        } else {
            // For non-notDetermined status, just use requestAccess
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            print("Microphone permission result: \(granted)")
            await MainActor.run {
                microphoneStatus = granted ? .granted : .denied
            }
            return granted
        }
    }

    /// Request microphone permission and ensure app appears in System Settings
    /// This should be called before opening the microphone settings page
    func ensureMicrophonePermissionRequested() async {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        print("ensureMicrophonePermissionRequested - current status: \(statusDescription(status))")

        // If not determined, request permission (this will show dialog and add app to list)
        if status == .notDetermined {
            print("Status is notDetermined, requesting permission...")
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        // If denied, the app should already be in the list from a previous request
        // If restricted, we can't do anything - it's controlled by parental controls/MDM
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

    // MARK: - Accessibility (for global keyboard shortcuts)

    func checkAccessibilityPermission() {
        // AXIsProcessTrusted checks if the app has Accessibility permission
        let isTrusted = AXIsProcessTrusted()
        accessibilityStatus = isTrusted ? .granted : .notDetermined
    }

    func requestAccessibilityPermission() {
        // Show system prompt to request accessibility access
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        accessibilityStatus = isTrusted ? .granted : .denied

        if !isTrusted {
            print("Accessibility permission not granted. Please enable it in System Settings > Privacy & Security > Accessibility")
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
