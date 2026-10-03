//
//  TextInsertion.swift
//  justscribe
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

/// How a dictation's text reaches the app the user is in.
nonisolated enum TextInsertionMode: String, Codable, CaseIterable, Sendable {
    /// The finished text is put on the clipboard and pasted once with ⌘V. Nothing is typed while
    /// speaking, so fields that mishandle synthetic keystrokes get one clean insertion.
    case paste
    /// Text is typed with synthetic keystrokes as it is recognised, then corrected in place.
    case type

    static let defaultMode = TextInsertionMode.paste

    /// The mode a stored raw value means; anything missing or unknown is the default.
    static func stored(_ rawValue: String?) -> TextInsertionMode {
        rawValue.flatMap(TextInsertionMode.init(rawValue:)) ?? defaultMode
    }

    var insertsWhileSpeaking: Bool { self == .type }

    var displayName: String {
        switch self {
        case .paste: "Paste when done"
        case .type: "Type as you speak"
        }
    }

    var detail: String {
        switch self {
        case .paste: "One clean insertion when you release the key. Works in fields that handle typed keystrokes badly; apps that intercept ⌘V may not take it. With Copy to Clipboard off, your previous clipboard is put back afterwards."
        case .type: "Text appears as you speak and is corrected in place. Use this where pasting does not work."
        }
    }
}

/// What to do with the finished text when a recording ends, decided without AppKit.
nonisolated enum TextInsertion {
    enum FinalAction: Equatable, Sendable {
        case paste(String, restoreClipboard: Bool)
        /// The app cannot post keystrokes (no Accessibility permission): the text is copied so the
        /// user still gets it, whatever the mode or the copy setting.
        case copyOnly(String)
        case nothing
    }

    /// Paste mode pastes non-blank text once; typing mode has already typed it. With "Copy to
    /// Clipboard" off, the clipboard is put back as it was after the paste. `canInsert` is the
    /// Accessibility permission: without it every posted keystroke vanishes silently.
    static func finalAction(mode: TextInsertionMode, text: String, copyToClipboard: Bool, canInsert: Bool = true) -> FinalAction {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .nothing }
        guard canInsert else { return .copyOnly(text) }
        guard mode == .paste else { return .nothing }
        return .paste(text, restoreClipboard: !copyToClipboard)
    }

    /// Whether a paste already left the text on the clipboard, so a separate copy is redundant.
    static func leavesTextOnClipboard(mode: TextInsertionMode, copyToClipboard: Bool) -> Bool {
        mode == .paste && copyToClipboard
    }
}
