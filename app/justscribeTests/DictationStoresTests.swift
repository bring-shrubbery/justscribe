//
//  DictationStoresTests.swift
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

import Foundation
import Testing
@testable import justscribe

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct DictationStoresTests {

    private func tempFile(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("justscribe-dictation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }
    private func cleanUp(_ url: URL) { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    // MARK: Vocabulary

    @Test func vocabularyRoundTripsAndKeepsNewestFirst() throws {
        let url = try tempFile("vocabulary.json"); defer { cleanUp(url) }
        let store = VocabularyStore(fileURL: url); store.load()
        #expect(store.entries.isEmpty)
        store.add(text: "Quassum", heardAs: [])
        store.add(text: "SwiftUI", heardAs: ["swift ui", " Swift-UI "])
        #expect(store.entries.map(\.text) == ["SwiftUI", "Quassum"])
        #expect(store.entries[0].heardAs == ["swift ui", "Swift-UI"])
        let again = VocabularyStore(fileURL: url); again.load()
        #expect(again.entries == store.entries)
    }

    @Test func vocabularyUpdateDeleteAndImport() throws {
        let url = try tempFile("vocabulary.json"); defer { cleanUp(url) }
        let store = VocabularyStore(fileURL: url); store.load()
        store.add(text: "Antoni", heardAs: [])
        var e = store.entries[0]; e.heardAs = ["antony"]; store.update(e)
        #expect(store.entries[0].heardAs == ["antony"])
        let added = store.importLines("""
            Quassum
            SwiftUI = swift ui, swift-ui

            Antoni
            """)
        #expect(added == 2)   // Antoni already exists
        #expect(store.entries.map(\.text) == ["Quassum", "SwiftUI", "Antoni"])   // pasted order first
        #expect(store.entries[1].heardAs == ["swift ui", "swift-ui"])
        store.delete(store.entries[1].id)
        #expect(store.entries.map(\.text) == ["Quassum", "Antoni"])
        let again = VocabularyStore(fileURL: url); again.load()
        #expect(again.entries.map(\.text) == ["Quassum", "Antoni"])
    }

    @Test func importKeepsThePastedOrderAndSkipsAnEmptyText() throws {
        let url = try tempFile("vocabulary.json"); defer { cleanUp(url) }
        let store = VocabularyStore(fileURL: url); store.load()
        store.add(text: "Old", heardAs: [])
        #expect(store.importLines("A\nB") == 2)
        #expect(store.entries.map(\.text) == ["A", "B", "Old"])
        let again = VocabularyStore(fileURL: url); again.load()
        #expect(again.entries.map(\.text) == ["A", "B", "Old"])
        #expect(store.importLines("= x") == 0)
        #expect(store.importLines("  = x, y") == 0)
        #expect(store.entries.map(\.text) == ["A", "B", "Old"])
    }

    @Test func updatingAnEntryToBlankTextLeavesItUnchanged() throws {
        let url = try tempFile("vocabulary.json"); defer { cleanUp(url) }
        let store = VocabularyStore(fileURL: url); store.load()
        store.add(text: "Quassum", heardAs: ["kwassum"])
        var e = store.entries[0]; e.text = "   "; e.heardAs = []
        store.update(e)
        #expect(store.entries.map(\.text) == ["Quassum"])
        #expect(store.entries[0].heardAs == ["kwassum"])
    }

    @Test func aDamagedVocabularyFileIsSetAside() throws {
        let url = try tempFile("vocabulary.json"); defer { cleanUp(url) }
        try "nope".write(to: url, atomically: true, encoding: .utf8)
        let store = VocabularyStore(fileURL: url); store.load()
        #expect(store.entries.isEmpty)
        #expect(store.fileWasSetAside)
        #expect(FileManager.default.fileExists(atPath: url.path + ".broken"))
    }

    // MARK: Modes

    @Test func modesStartWithDefaultAndKeepItFirst() throws {
        let url = try tempFile("modes.json"); defer { cleanUp(url) }
        let store = ModeStore(fileURL: url); store.load()
        #expect(store.modes.map(\.name) == ["Default"])
        #expect(store.modes[0].id == DictationMode.defaultID)
        #expect(store.modes[0].instructions == DictationMode.defaultInstructions)
        store.add(DictationMode(id: UUID(), name: "Email", instructions: "Formal.", cleanUp: true, appBundleIDs: ["com.apple.mail"]))
        let again = ModeStore(fileURL: url); again.load()
        #expect(again.modes.map(\.name) == ["Default", "Email"])
    }

    @Test func anAppBelongsToOneModeAndSelectionFallsBackToDefault() throws {
        let url = try tempFile("modes.json"); defer { cleanUp(url) }
        let store = ModeStore(fileURL: url); store.load()
        let email = DictationMode(id: UUID(), name: "Email", instructions: "Formal.", cleanUp: true, appBundleIDs: ["com.apple.mail"])
        let code = DictationMode(id: UUID(), name: "Code", instructions: "", cleanUp: false, appBundleIDs: [])
        store.add(email); store.add(code)
        #expect(store.mode(forApp: "com.apple.mail").name == "Email")
        #expect(store.mode(forApp: "com.apple.Notes").name == "Default")
        #expect(store.mode(forApp: nil).name == "Default")
        store.assign(app: "com.apple.mail", to: code.id)
        #expect(store.mode(forApp: "com.apple.mail").name == "Code")
        #expect(store.modes.first { $0.id == email.id }?.appBundleIDs.isEmpty == true)
    }

    @Test func defaultCannotBeDeletedAndBlankInstructionsFallBack() throws {
        let url = try tempFile("modes.json"); defer { cleanUp(url) }
        let store = ModeStore(fileURL: url); store.load()
        store.delete(DictationMode.defaultID)
        #expect(store.modes.count == 1)
        var d = store.modes[0]; d.instructions = "   "; store.update(d)
        #expect(store.modes[0].effectiveInstructions == DictationMode.defaultInstructions)
    }

    @Test func aDamagedModesFileIsSetAsideAndDefaultRecreated() throws {
        let url = try tempFile("modes.json"); defer { cleanUp(url) }
        try "nope".write(to: url, atomically: true, encoding: .utf8)
        let store = ModeStore(fileURL: url); store.load()
        #expect(store.fileWasSetAside)
        #expect(store.modes.map(\.name) == ["Default"])
    }

    // MARK: Trigger and prompt

    @Test func recordingTriggerStoresAndDefaults() {
        #expect(RecordingTrigger.stored(nil) == .hold)
        #expect(RecordingTrigger.stored("toggle") == .pressToToggle)
        #expect(RecordingTrigger.stored("garbage") == .hold)
        #expect(RecordingTrigger.pressToToggle.rawValue == "toggle")
    }

    @Test func vocabularyPromptListsNewestFirst() {
        let old = VocabularyEntry(id: UUID(), text: "Quassum", heardAs: [], createdAt: Date(timeIntervalSince1970: 1))
        let new = VocabularyEntry(id: UUID(), text: "SwiftUI", heardAs: ["swift ui"], createdAt: Date(timeIntervalSince1970: 2))
        #expect(VocabularyPrompt.text([old, new]) == "SwiftUI Quassum")
        #expect(VocabularyPrompt.text([]) == "")
    }
}
