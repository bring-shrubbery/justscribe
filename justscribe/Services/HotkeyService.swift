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

@Observable
final class HotkeyService {
    static let shared = HotkeyService()

    private(set) var isEnabled = false

    var onActivate: (() -> Void)?

    private init() {}

    func setup() {
        // Set default shortcut if none configured
        if KeyboardShortcuts.getShortcut(for: .activateTranscription) == nil {
            setDefaultShortcut()
        }

        KeyboardShortcuts.onKeyUp(for: .activateTranscription) { [weak self] in
            self?.onActivate?()
        }
        isEnabled = true
    }

    func disable() {
        isEnabled = false
    }

    func setDefaultShortcut() {
        // Set default shortcut to Control + Shift + Space
        KeyboardShortcuts.setShortcut(.init(.space, modifiers: [.control, .shift]), for: .activateTranscription)
    }
}
