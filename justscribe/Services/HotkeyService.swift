//
//  HotkeyService.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import Foundation
import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let activateTranscription = Self("activateTranscription")
}

@MainActor
@Observable
final class HotkeyService {
    static let shared = HotkeyService()

    private(set) var isEnabled = false

    var onActivate: (() -> Void)?

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

        // Use onKeyDown for immediate response
        KeyboardShortcuts.onKeyDown(for: .activateTranscription) { [weak self] in
            print("Shortcut key down detected!")
            Task { @MainActor in
                self?.onActivate?()
            }
        }

        isEnabled = true
        print("HotkeyService enabled")
    }

    func disable() {
        KeyboardShortcuts.disable(.activateTranscription)
        isEnabled = false
    }

    func setDefaultShortcut() {
        // Set default shortcut to Control + Shift + Space
        let shortcut = KeyboardShortcuts.Shortcut(.space, modifiers: [.control, .shift])
        KeyboardShortcuts.setShortcut(shortcut, for: .activateTranscription)
        print("Default shortcut set: \(shortcut)")
    }

    func resetShortcut() {
        KeyboardShortcuts.reset(.activateTranscription)
        setDefaultShortcut()
    }
}
