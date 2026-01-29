//
//  ClipboardService.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import Foundation
import AppKit
import Carbon.HIToolbox

final class ClipboardService {
    static let shared = ClipboardService()

    private init() {}

    func copyToClipboard(_ text: String) {
        print("Copying to clipboard: \(text.prefix(50))...")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let success = pasteboard.setString(text, forType: .string)
        print("Clipboard copy success: \(success)")
    }

    func pasteFromClipboard() -> String? {
        return NSPasteboard.general.string(forType: .string)
    }

    /// Simulates Cmd+V to paste clipboard contents into the focused app
    func simulatePaste() {
        print("Simulating Cmd+V paste...")

        // Create key down event for Cmd+V
        let source = CGEventSource(stateID: .hidSystemState)

        // V key code is 9
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)

        // Add Command modifier
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        // Post the events
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        print("Paste simulation completed")
    }

    /// Copy text to clipboard and paste it into the focused input
    func copyAndPaste(_ text: String) {
        copyToClipboard(text)
        // Small delay to ensure clipboard is updated before pasting
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.simulatePaste()
        }
    }
}
