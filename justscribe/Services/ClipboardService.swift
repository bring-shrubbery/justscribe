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
        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)

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

    /// Type text directly using keyboard events (for real-time typing)
    /// This types text character by character into the focused application
    func typeText(_ text: String) {
        guard !text.isEmpty else {
            print("typeText: empty text, skipping")
            return
        }

        print("typeText: typing '\(text)' (\(text.count) characters)")

        let source = CGEventSource(stateID: .hidSystemState)

        if source == nil {
            print("typeText: ERROR - Could not create CGEventSource")
            return
        }

        var typedCount = 0
        for character in text {
            // Use CGEvent with Unicode string for proper character support
            if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {

                // Set the Unicode string for the character
                var unicodeChar = Array(String(character).utf16)
                keyDown.keyboardSetUnicodeString(stringLength: unicodeChar.count, unicodeString: &unicodeChar)
                keyUp.keyboardSetUnicodeString(stringLength: unicodeChar.count, unicodeString: &unicodeChar)

                // Post the events to the session (works better for most apps)
                keyDown.post(tap: .cgSessionEventTap)
                keyUp.post(tap: .cgSessionEventTap)

                typedCount += 1

                // Small delay between characters for reliability
                usleep(2000) // 2ms
            } else {
                print("typeText: ERROR - Could not create CGEvent for character '\(character)'")
            }
        }

        print("typeText: finished typing \(typedCount) characters")
    }

    /// Type new text, appending to what was previously typed
    /// Useful for streaming transcription where we only want to type the delta
    /// Uses clipboard paste to avoid conflicts with held modifier keys
    func typeNewText(fullText: String, previouslyTypedLength: Int) -> Int {
        guard fullText.count > previouslyTypedLength else {
            return previouslyTypedLength
        }

        let startIndex = fullText.index(fullText.startIndex, offsetBy: previouslyTypedLength)
        let newText = String(fullText[startIndex...])

        if !newText.isEmpty {
            // Use paste instead of typeText to avoid modifier key conflicts
            // (user is holding Ctrl+Shift while we type, which would trigger shortcuts)
            pasteText(newText)
        }

        return fullText.count
    }

    /// Paste text using clipboard (safer than typing when modifiers are held)
    func pasteText(_ text: String) {
        guard !text.isEmpty else { return }

        print("pasteText: pasting '\(text)' (\(text.count) characters)")

        // Save current clipboard content
        let pasteboard = NSPasteboard.general
        let previousContent = pasteboard.string(forType: .string)

        // Set new content and paste
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay to ensure clipboard is updated
        usleep(10000) // 10ms

        // Simulate Cmd+V (without other modifiers)
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)

        // Only Command modifier, no Control or Shift
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)

        // Restore previous clipboard content after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let previous = previousContent {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }

        print("pasteText: completed")
    }
}
