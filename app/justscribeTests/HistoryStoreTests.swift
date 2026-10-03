//
//  HistoryStoreTests.swift
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
struct HistoryStoreTests {

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("justscribe-history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func tone(seconds: Double) -> [Float] {
        (0..<Int(seconds * 16_000)).map { sinf(2 * .pi * 440 * Float($0) / 16_000) * 0.5 }
    }

    private func record(_ text: String, at seconds: TimeInterval, audio: String? = nil) -> DictationRecord {
        DictationRecord(id: UUID(), createdAt: Date(timeIntervalSince1970: seconds), text: text,
                        durationSeconds: 1, modelID: "fluidaudio:v3", language: "en", audioFileName: audio)
    }

    @Test func aNewDirectoryIsAnEmptyHistory() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir)
        store.load()
        #expect(store.records.isEmpty)
        #expect(store.audioBytes == 0)
        #expect(!store.indexWasSetAside)
    }

    @Test func addingTextOnlyPersistsNewestFirst() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir)
        store.load()
        await store.add(text: "first", durationSeconds: 2, modelID: "fluidaudio:v3", language: "en", audio: nil)
        await store.add(text: "second", durationSeconds: 3, modelID: "whisperkit:base", language: nil, audio: nil)
        #expect(store.records.map(\.text) == ["second", "first"])
        #expect(store.records[0].audioFileName == nil)

        let reloaded = HistoryStore(directory: dir)
        reloaded.load()
        #expect(reloaded.records == store.records)
    }

    @Test func addingWithAudioWritesTheFileAndCountsItsBytes() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir)
        store.load()
        await store.add(text: "with audio", durationSeconds: 3, modelID: "fluidaudio:v3", language: "en", audio: tone(seconds: 3))
        let name = try #require(store.records[0].audioFileName)
        let url = try #require(store.audioURL(for: store.records[0]))
        #expect(url.lastPathComponent == name)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(store.audioBytes > 1_000)
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        #expect(store.audioBytes == size)
    }

    @Test func deleteRemovesTheRecordAndItsFile() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir)
        store.load()
        await store.add(text: "keep", durationSeconds: 1, modelID: "m", language: nil, audio: nil)
        await store.add(text: "drop", durationSeconds: 1, modelID: "m", language: nil, audio: tone(seconds: 1))
        let url = try #require(store.audioURL(for: store.records[0]))
        store.delete(store.records[0].id)
        #expect(store.records.map(\.text) == ["keep"])
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(store.audioBytes == 0)
    }

    @Test func deleteAllEmptiesEverything() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir)
        store.load()
        await store.add(text: "a", durationSeconds: 1, modelID: "m", language: nil, audio: tone(seconds: 1))
        await store.add(text: "b", durationSeconds: 1, modelID: "m", language: nil, audio: nil)
        store.deleteAll()
        #expect(store.records.isEmpty)
        #expect(store.audioBytes == 0)
        let audioDir = dir.appendingPathComponent("audio")
        let left = (try? FileManager.default.contentsOfDirectory(atPath: audioDir.path)) ?? []
        #expect(left.isEmpty)
        let reloaded = HistoryStore(directory: dir)
        reloaded.load()
        #expect(reloaded.records.isEmpty)
    }

    @Test func searchIgnoresCaseAndDiacriticsAndAnEmptyQueryShowsAll() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir)
        store.load()
        await store.add(text: "Meet at the café at noon", durationSeconds: 1, modelID: "m", language: nil, audio: nil)
        await store.add(text: "Nothing to do with coffee", durationSeconds: 1, modelID: "m", language: nil, audio: nil)
        #expect(store.search("CAFE").map(\.text) == ["Meet at the café at noon"])
        #expect(store.search("  ").count == 2)
        #expect(store.search("zzz").isEmpty)
        #expect(HistoryStore.matches("Ünïcode", query: "unicode"))
    }

    @Test func theCapRemovesTheOldestAudioAndKeepsItsText() {
        let old = record("old", at: 100, audio: "old.m4a")
        let mid = record("mid", at: 200, audio: "mid.m4a")
        let new = record("new", at: 300, audio: "new.m4a")
        let sizes = ["old.m4a": 400, "mid.m4a": 400, "new.m4a": 400]
        // Newest first, as the store keeps them.
        #expect(HistoryStore.audioToRemove(records: [new, mid, old], sizes: sizes, cap: 1_000) == ["old.m4a"])
        #expect(HistoryStore.audioToRemove(records: [new, mid, old], sizes: sizes, cap: 500) == ["old.m4a", "mid.m4a"])
        #expect(HistoryStore.audioToRemove(records: [new, mid, old], sizes: sizes, cap: 1_200).isEmpty)
    }

    @Test func aSingleFileOverTheCapIsRemovedItself() {
        let only = record("huge", at: 100, audio: "huge.m4a")
        #expect(HistoryStore.audioToRemove(records: [only], sizes: ["huge.m4a": 2_000], cap: 1_000) == ["huge.m4a"])
    }

    @Test func theCapIsEnforcedAfterAnAddition() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        // A 3 s tone encodes to about 38.5 kB here (AVAudioFile adds a ~23.5 kB `free` atom per
        // file), so 58 kB is about 1.5 recordings: one fits, two do not.
        let store = HistoryStore(directory: dir, audioCap: 58_000)
        store.load()
        await store.add(text: "first", durationSeconds: 3, modelID: "m", language: nil, audio: tone(seconds: 3))
        await store.add(text: "second", durationSeconds: 3, modelID: "m", language: nil, audio: tone(seconds: 3))
        #expect(store.records.map(\.text) == ["second", "first"])
        #expect(store.records[1].audioFileName == nil)      // oldest lost its audio…
        #expect(store.records[0].audioFileName != nil)      // …the newest kept it
        #expect(store.audioBytes <= 58_000)
        let audioDir = dir.appendingPathComponent("audio")
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: audioDir.path)) ?? []).count == 1)
    }

    @Test func anUnreadableIndexIsSetAsideNotOverwritten() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "not json".write(to: dir.appendingPathComponent("index.json"), atomically: true, encoding: .utf8)
        let store = HistoryStore(directory: dir)
        store.load()
        #expect(store.records.isEmpty)
        #expect(store.indexWasSetAside)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("index.json.broken").path))
        #expect(try String(contentsOf: dir.appendingPathComponent("index.json.broken"), encoding: .utf8) == "not json")
    }

    @Test func loadRemovesAudioNoRecordNamesAndDropsNamesWithoutFiles() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let audioDir = dir.appendingPathComponent("audio")
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: audioDir.appendingPathComponent("orphan.m4a"))
        let index = HistoryIndex(version: 1, records: [record("lost its file", at: 1, audio: "gone.m4a")])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(index).write(to: dir.appendingPathComponent("index.json"))

        let store = HistoryStore(directory: dir)
        store.load()
        #expect(!FileManager.default.fileExists(atPath: audioDir.appendingPathComponent("orphan.m4a").path))
        #expect(store.records.count == 1)
        #expect(store.records[0].audioFileName == nil)
        #expect(store.audioURL(for: store.records[0]) == nil)
    }

    @Test func twoAdditionsInFlightBothLand() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir)
        store.load()
        async let a: Void = store.add(text: "a", durationSeconds: 3, modelID: "m", language: nil, audio: tone(seconds: 3))
        async let b: Void = store.add(text: "b", durationSeconds: 3, modelID: "m", language: nil, audio: tone(seconds: 3))
        _ = await (a, b)
        #expect(Set(store.records.map(\.text)) == ["a", "b"])
        #expect(store.records.allSatisfy { $0.audioFileName != nil })
        let reloaded = HistoryStore(directory: dir)
        reloaded.load()
        #expect(reloaded.records.count == 2)
    }

    @Test func aFailedIndexWriteKeepsMemoryAndDiskInStep() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir)
        store.load()
        await store.add(text: "before", durationSeconds: 1, modelID: "m", language: nil, audio: nil)
        // Make the directory unwritable, then try to add.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path) }
        await store.add(text: "after", durationSeconds: 1, modelID: "m", language: nil, audio: nil)
        #expect(store.records.map(\.text) == ["before"])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        let reloaded = HistoryStore(directory: dir)
        reloaded.load()
        #expect(reloaded.records.map(\.text) == ["before"])
    }
}
