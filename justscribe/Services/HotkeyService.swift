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
    private var modifierOnlyMonitor: Any?
    private var activationTimer: DispatchWorkItem?
    private var isModifierOnlyMode = false

    private init() {}

    func setup() {
        // Load shortcut config (with migration from KeyboardShortcuts library)
        let config = ShortcutConfig.load() ?? {
            let defaultConfig = ShortcutConfig.defaultConfig
            defaultConfig.save()
            return defaultConfig
        }()

        print("Setting up hotkey with config: \(config.displayString) (modifierOnly: \(config.isModifierOnly))")

        if config.isModifierOnly {
            // Modifier-only mode: use custom flagsChanged monitor
            KeyboardShortcuts.disable(.activateTranscription)
            isModifierOnlyMode = true
            setupModifierOnlyMonitor(for: config)
        } else {
            // Modifier+key mode: use KeyboardShortcuts library (Carbon Events)
            isModifierOnlyMode = false
            syncConfigToKeyboardShortcuts(config)

            KeyboardShortcuts.onKeyDown(for: .activateTranscription) { [weak self] in
                print("Shortcut key down detected!")
                Task { @MainActor in
                    self?.isShortcutHeld = true
                    self?.onKeyDown?()
                }
            }

            setupKeyUpMonitor(for: config)
        }

        isEnabled = true
        print("HotkeyService enabled")
    }

    // MARK: - Modifier+Key Mode (existing Carbon Events path)

    private func syncConfigToKeyboardShortcuts(_ config: ShortcutConfig) {
        if let shortcut = config.toKeyboardShortcut() {
            KeyboardShortcuts.setShortcut(shortcut, for: .activateTranscription)
            print("Synced to KeyboardShortcuts: \(shortcut)")
        }
    }

    private func setupKeyUpMonitor(for config: ShortcutConfig) {
        removeKeyUpMonitors()

        guard let keyCode = config.keyCode else { return }
        let targetKeyCode = UInt16(keyCode)
        let requiredModifiers = config.modifierFlags

        // Monitor for key up events
        keyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self = self else { return }

            if event.keyCode == targetKeyCode {
                Task { @MainActor in
                    if self.isShortcutHeld {
                        print("Shortcut key up detected!")
                        self.isShortcutHeld = false
                        self.onKeyUp?()
                    }
                }
            }
        }

        // Also monitor for modifier flag changes (in case modifiers are released first)
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return }

            Task { @MainActor in
                if self.isShortcutHeld {
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

    // MARK: - Modifier-Only Mode

    private func setupModifierOnlyMonitor(for config: ShortcutConfig) {
        removeModifierOnlyMonitor()

        let required = config.modifierFlags
        let relevantMask: NSEvent.ModifierFlags = [.control, .shift, .option, .command]

        modifierOnlyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return }

            let current = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .intersection(relevantMask)

            Task { @MainActor in
                if !self.isShortcutHeld {
                    // Check for activation: exact match of required modifiers
                    if current == required {
                        // Start activation timer to prevent false triggers
                        self.activationTimer?.cancel()
                        let timer = DispatchWorkItem { [weak self] in
                            Task { @MainActor in
                                guard let self = self, !self.isShortcutHeld else { return }
                                print("Modifier-only shortcut activated!")
                                self.isShortcutHeld = true
                                self.onKeyDown?()
                            }
                        }
                        self.activationTimer = timer
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: timer)
                    } else {
                        // Modifiers changed away from required before timer fired
                        self.activationTimer?.cancel()
                        self.activationTimer = nil
                    }
                } else {
                    // Check for deactivation: any required modifier released
                    let stillHeld = current.contains(required)
                    if !stillHeld {
                        print("Modifier-only shortcut deactivated!")
                        self.activationTimer?.cancel()
                        self.activationTimer = nil
                        self.isShortcutHeld = false
                        self.onKeyUp?()
                    }
                }
            }
        }

        print("Modifier-only monitor set up for: \(config.displayString)")
    }

    // MARK: - Cleanup

    private func removeKeyUpMonitors() {
        if let monitor = keyUpMonitor {
            NSEvent.removeMonitor(monitor)
            keyUpMonitor = nil
        }
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
    }

    private func removeModifierOnlyMonitor() {
        activationTimer?.cancel()
        activationTimer = nil
        if let monitor = modifierOnlyMonitor {
            NSEvent.removeMonitor(monitor)
            modifierOnlyMonitor = nil
        }
    }

    func disable() {
        KeyboardShortcuts.disable(.activateTranscription)
        removeKeyUpMonitors()
        removeModifierOnlyMonitor()

        isEnabled = false
        isShortcutHeld = false
        isModifierOnlyMode = false
    }

    // MARK: - Shortcut Management

    func setDefaultShortcut() {
        let config = ShortcutConfig.defaultConfig
        config.save()

        if isEnabled {
            disable()
            setup()
        }

        print("Default shortcut set: \(config.displayString)")
    }

    func resetShortcut() {
        KeyboardShortcuts.reset(.activateTranscription)
        ShortcutConfig.clear()
        setDefaultShortcut()
    }

    /// Call this when the shortcut is changed in settings
    func shortcutDidChange() {
        disable()
        setup()
    }
}
