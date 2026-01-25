//
//  HotkeyService.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import Foundation
import Combine

// Note: This service will use the KeyboardShortcuts library once added via SPM.
// For now, this is a placeholder implementation.

@Observable
final class HotkeyService {
    static let shared = HotkeyService()

    private(set) var isEnabled = false
    private(set) var currentShortcut: ShortcutKey?

    var onActivate: (() -> Void)?

    struct ShortcutKey: Equatable {
        let keyCode: UInt16
        let modifiers: UInt
    }

    private init() {}

    func setup() {
        // Will be implemented with KeyboardShortcuts library
        // KeyboardShortcuts.onKeyUp(for: .activateTranscription) { [weak self] in
        //     self?.onActivate?()
        // }
    }

    func updateShortcut(keyCode: UInt16, modifiers: UInt) {
        currentShortcut = ShortcutKey(keyCode: keyCode, modifiers: modifiers)
        // Will update KeyboardShortcuts binding
    }

    func enable() {
        isEnabled = true
    }

    func disable() {
        isEnabled = false
    }
}
