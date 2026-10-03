//
//  ClipboardService.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
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
            paste(newText, restorePrevious: true)
        }

        return fullText.count
    }

    /// Delete N characters backward then paste replacement text
    func replaceTypedText(characterCount: Int, withText newText: String) {
        guard characterCount > 0, !newText.isEmpty else { return }

        print("replaceTypedText: deleting \(characterCount) chars, replacing with '\(newText.prefix(50))...'")

        let source = CGEventSource(stateID: .hidSystemState)

        // Select all typed text using Shift+Home-like approach won't work universally,
        // so we send individual backspace events
        // For very long texts, use Cmd+A select-all approach as fallback
        if characterCount > 500 {
            // For long texts: select all with Cmd+A then delete
            // This is a heuristic — works when the field only contains our text
            if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_A), keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_A), keyDown: false) {
                keyDown.flags = .maskCommand
                keyUp.flags = .maskCommand
                keyDown.post(tap: .cgSessionEventTap)
                keyUp.post(tap: .cgSessionEventTap)
                usleep(10000) // 10ms
            }
            // Delete the selection
            if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Delete), keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Delete), keyDown: false) {
                keyDown.post(tap: .cgSessionEventTap)
                keyUp.post(tap: .cgSessionEventTap)
                usleep(5000) // 5ms
            }
        } else {
            // Send backspace events to delete the raw text
            for _ in 0..<characterCount {
                if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Delete), keyDown: true),
                   let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Delete), keyDown: false) {
                    keyDown.post(tap: .cgSessionEventTap)
                    keyUp.post(tap: .cgSessionEventTap)
                    usleep(1000) // 1ms between keystrokes
                }
            }
        }

        // Small delay for the app to process all deletions
        usleep(20000) // 20ms

        // Paste the corrected text
        paste(newText, restorePrevious: true)

        print("replaceTypedText: completed")
    }

    /// Puts `text` on the clipboard and pastes it into the focused app with one ⌘V. With
    /// `restorePrevious`, whatever was on the clipboard before (text, an image, a file…) is put
    /// back `restoreDelay` later, unless something else was copied in the meantime. The delay
    /// is the time the target app gets to read the pasteboard before it changes under it.
    func paste(_ text: String, restorePrevious: Bool, restoreDelay: TimeInterval = 0.2) {
        guard !text.isEmpty else { return }

        print("paste: pasting \(text.count) characters (restore previous: \(restorePrevious))")

        let pasteboard = NSPasteboard.general
        let previous = restorePrevious ? ClipboardSnapshot(of: pasteboard) : nil

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ours = pasteboard.changeCount

        // Give the pasteboard server a moment before the target app reads it.
        usleep(10000) // 10ms

        // ⌘V with no other modifier, whatever keys the user is still holding.
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)

        // The target app reads the pasteboard when it handles ⌘V; restore after it has had time to,
        // and only if the clipboard still holds our text (the user may have copied something since).
        if let previous {
            DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
                guard pasteboard.changeCount == ours else { return }
                previous.restore(to: pasteboard)
            }
        }

        print("paste: completed")
    }
}

/// What is on a pasteboard, so it can be put back after a paste: every item with every
/// representation it carries, up to a size cap. Past the cap only the text is kept, so a huge
/// image or a file promise from another app cannot stall the paste. `dyn.*` types are left
/// out: the system derives them from the real types on demand. An empty pasteboard restores
/// as empty.
struct ClipboardSnapshot {
    /// The most data a snapshot holds before falling back to text only.
    static let sizeCap = 16 * 1024 * 1024

    private(set) var items: [[NSPasteboard.PasteboardType: Data]]
    /// True when the cap was hit and only text was kept.
    private(set) var isTextOnly = false

    init(of pasteboard: NSPasteboard, sizeCap: Int = ClipboardSnapshot.sizeCap) {
        var total = 0
        var items: [[NSPasteboard.PasteboardType: Data]] = []
        var capped = false
        for item in pasteboard.pasteboardItems ?? [] {
            var data: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types where !type.rawValue.hasPrefix("dyn.") {
                guard !capped, let value = item.data(forType: type) else { continue }
                total += value.count
                if total > sizeCap {
                    capped = true
                    break
                }
                data[type] = value
            }
            items.append(data)
        }
        if capped {
            let text = pasteboard.string(forType: .string)
            items = text.map { [[.string: Data($0.utf8)]] } ?? []
            isTextOnly = true
        }
        self.items = items
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.map { data in
            let item = NSPasteboardItem()
            for (type, value) in data { item.setData(value, forType: type) }
            return item
        }
        if !restored.isEmpty {
            pasteboard.writeObjects(restored)
        }
    }
}
