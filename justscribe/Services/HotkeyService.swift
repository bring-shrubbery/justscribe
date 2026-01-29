//
//  HotkeyService.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import Foundation
import AppKit
import KeyboardShortcuts
import Carbon.HIToolbox

extension KeyboardShortcuts.Name {
    static let activateTranscription = Self("activateTranscription")
}

@MainActor
@Observable
final class HotkeyService {
    static let shared = HotkeyService()

    private(set) var isEnabled = false
    private(set) var isShortcutHeld = false

    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    // Legacy callback for backwards compatibility
    var onActivate: (() -> Void)? {
        get { onKeyDown }
        set { onKeyDown = newValue }
    }

    private var keyUpMonitor: Any?
    private var flagsMonitor: Any?

    private init() {}

    func setup() {
        // Set default shortcut if none configured
        if KeyboardShortcuts.getShortcut(for: .activateTranscription) == nil {
            print("No shortcut configured, setting default...")
            setDefaultShortcut()
        }

        // Log current shortcut
        if let shortcut = KeyboardShortcuts.getShortcut(for: .activateTranscription) {
            print("Registered shortcut: \(shortcut)")
        } else {
            print("WARNING: No shortcut registered!")
        }

        // Use KeyboardShortcuts for key down detection (works globally)
        KeyboardShortcuts.onKeyDown(for: .activateTranscription) { [weak self] in
            print("Shortcut key down detected!")
            Task { @MainActor in
                self?.isShortcutHeld = true
                self?.onKeyDown?()
            }
        }

        // Monitor for key up events globally using NSEvent
        setupKeyUpMonitor()

        isEnabled = true
        print("HotkeyService enabled")
    }

    private func setupKeyUpMonitor() {
        // Remove existing monitors
        if let monitor = keyUpMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
        }

        guard let shortcut = KeyboardShortcuts.getShortcut(for: .activateTranscription) else {
            print("No shortcut to monitor for key up")
            return
        }

        // Get the key code from the shortcut
        let targetKeyCode = shortcut.carbonKeyCode

        // Monitor for key up events
        keyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self = self else { return }

            print("Key up event: keyCode=\(event.keyCode), target=\(targetKeyCode)")

            // Check if it's the same key
            if event.keyCode == targetKeyCode {
                Task { @MainActor in
                    if self.isShortcutHeld {
                        print("Shortcut key up detected! Triggering onKeyUp")
                        self.isShortcutHeld = false
                        self.onKeyUp?()
                    } else {
                        print("Key up detected but isShortcutHeld was false")
                    }
                }
            }
        }

        // Also monitor for modifier flag changes (in case modifiers are released first)
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return }

            Task { @MainActor in
                if self.isShortcutHeld {
                    // Check if required modifiers are still held
                    let requiredModifiers = shortcut.modifiers
                    let currentModifiers = event.modifierFlags

                    var modifiersStillHeld = true

                    if requiredModifiers.contains(.control) && !currentModifiers.contains(.control) {
                        modifiersStillHeld = false
                    }
                    if requiredModifiers.contains(.shift) && !currentModifiers.contains(.shift) {
                        modifiersStillHeld = false
                    }
                    if requiredModifiers.contains(.option) && !currentModifiers.contains(.option) {
                        modifiersStillHeld = false
                    }
                    if requiredModifiers.contains(.command) && !currentModifiers.contains(.command) {
                        modifiersStillHeld = false
                    }

                    if !modifiersStillHeld {
                        print("Shortcut modifier released!")
                        self.isShortcutHeld = false
                        self.onKeyUp?()
                    }
                }
            }
        }

        print("Key up monitor set up for key code: \(targetKeyCode)")
    }

    func disable() {
        KeyboardShortcuts.disable(.activateTranscription)

        if let monitor = keyUpMonitor {
            NSEvent.removeMonitor(monitor)
            keyUpMonitor = nil
        }
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }

        isEnabled = false
        isShortcutHeld = false
    }

    func setDefaultShortcut() {
        // Set default shortcut to Control + Shift + Space
        let shortcut = KeyboardShortcuts.Shortcut(.space, modifiers: [.control, .shift])
        KeyboardShortcuts.setShortcut(shortcut, for: .activateTranscription)
        print("Default shortcut set: \(shortcut)")

        // Re-setup key up monitor for new shortcut
        if isEnabled {
            setupKeyUpMonitor()
        }
    }

    func resetShortcut() {
        KeyboardShortcuts.reset(.activateTranscription)
        setDefaultShortcut()
    }

    /// Call this when the shortcut is changed in settings
    func shortcutDidChange() {
        if isEnabled {
            setupKeyUpMonitor()
        }
    }
}
