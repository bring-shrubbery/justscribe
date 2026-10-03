//
//  TextInsertionTests.swift
//  justscribeTests
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

import Testing
@testable import justscribe

struct TextInsertionTests {

    // MARK: - The setting

    @Test func pasteIsTheDefaultForNewAndUnknownValues() {
        #expect(TextInsertionMode.stored(nil) == .paste)
        #expect(TextInsertionMode.stored("") == .paste)
        #expect(TextInsertionMode.stored("teleport") == .paste)
    }

    @Test func storedValuesRoundTrip() {
        for mode in TextInsertionMode.allCases {
            #expect(TextInsertionMode.stored(mode.rawValue) == mode)
        }
        #expect(TextInsertionMode.stored("type") == .type)
    }

    @Test func onlyTypingInsertsWhileSpeaking() {
        #expect(TextInsertionMode.type.insertsWhileSpeaking)
        #expect(!TextInsertionMode.paste.insertsWhileSpeaking)
    }

    // MARK: - What happens when the recording ends

    @Test func pasteModePastesTheFinishedTextOnce() {
        let action = TextInsertion.finalAction(mode: .paste, text: "Hello there.", copyToClipboard: true)
        #expect(action == .paste("Hello there.", restoreClipboard: false))
    }

    @Test func pasteModeRestoresTheClipboardWhenCopyingIsOff() {
        let action = TextInsertion.finalAction(mode: .paste, text: "Hello there.", copyToClipboard: false)
        #expect(action == .paste("Hello there.", restoreClipboard: true))
    }

    @Test func nothingIsPastedForBlankText() {
        #expect(TextInsertion.finalAction(mode: .paste, text: "", copyToClipboard: true) == .nothing)
        #expect(TextInsertion.finalAction(mode: .paste, text: "  \n", copyToClipboard: true) == .nothing)
    }

    @Test func typingModeNeverPastes() {
        #expect(TextInsertion.finalAction(mode: .type, text: "Hello there.", copyToClipboard: false) == .nothing)
    }

    @Test func pastingLeavesTheTextOnTheClipboardOnlyWhenCopyingIsOn() {
        #expect(TextInsertion.leavesTextOnClipboard(mode: .paste, copyToClipboard: true))
        #expect(!TextInsertion.leavesTextOnClipboard(mode: .paste, copyToClipboard: false))
        #expect(!TextInsertion.leavesTextOnClipboard(mode: .type, copyToClipboard: true))
    }
}
