//
//  TranscriptStoreTests.swift
//  justscribeTests
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
import Testing
@testable import justscribe

@MainActor
struct TranscriptStoreTests {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("TranscriptStoreTests-\(UUID().uuidString)", isDirectory: true)

    private func makeStore() -> TranscriptStore {
        TranscriptStore(directory: directory, remove: { try FileManager.default.removeItem(at: $0) })
    }

    private func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: string)!
    }

    @Test func fileNamesCarryTheDateAndTitleAndParseBack() {
        let when = date("2026-10-06 14:32:05")
        let name = TranscriptStore.fileName(title: "Long Dictation", date: when)
        #expect(name == "2026-10-06 14.32.05 Long Dictation.txt")
        let parsed = TranscriptStore.parse(fileName: name)
        #expect(parsed?.date == when)
        #expect(parsed?.title == "Long Dictation")
        // Characters a file name cannot hold are replaced; an empty title gets a word.
        #expect(TranscriptStore.fileName(title: "a/b: c", date: when).hasSuffix(" a-b- c.txt"))
        #expect(TranscriptStore.fileName(title: "  ", date: when).hasSuffix(" Transcript.txt"))
        #expect(TranscriptStore.parse(fileName: "notes.txt") == nil)
        #expect(TranscriptStore.parse(fileName: "2026-10-06 14.32.05.txt") == nil)
    }

    @Test func savingWritesAFileAndListsNewestFirst() throws {
        let store = makeStore()
        let first = try store.save("[00:00:00] You\nHello", title: "Live Transcription", date: date("2026-10-05 09:00:00"))
        let second = try store.save("[00:00:00] Speaker 1\nHi", title: "meeting", date: date("2026-10-06 10:00:00"))
        #expect(store.transcripts.map(\.title) == ["meeting", "Live Transcription"])
        #expect(store.transcripts.map(\.url) == [second.url, first.url])
        #expect(try store.text(of: first) == "[00:00:00] You\nHello")
        #expect(first.url.deletingLastPathComponent() == directory)
    }

    @Test func aNameAlreadyTakenGetsACounter() throws {
        let store = makeStore()
        let when = date("2026-10-06 10:00:00")
        let a = try store.save("a", title: "Long Dictation", date: when)
        let b = try store.save("b", title: "Long Dictation", date: when)
        #expect(a.url != b.url)
        #expect(b.url.lastPathComponent == "2026-10-06 10.00.00 Long Dictation 2.txt")
        #expect(try store.text(of: b) == "b")
    }

    @Test func filesNotNamedByTheAppAreListedByCreationDate() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "hello".write(to: directory.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        try "ignored".write(to: directory.appendingPathComponent("image.png"), atomically: true, encoding: .utf8)
        let store = makeStore()
        store.load()
        #expect(store.transcripts.map(\.title) == ["notes"])
        #expect(store.transcripts[0].date > .distantPast)
    }

    @Test func aRecordingIsMovedNextToItsTranscriptAndDeletedWithIt() throws {
        let store = makeStore()
        let recording = FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID().uuidString).m4a")
        try Data([1, 2, 3]).write(to: recording)
        let saved = try store.save("[00:00:00]\nHi", title: "Long Dictation", date: date("2026-10-07 09:00:00"), audio: recording)
        let audio = try #require(saved.audioURL)
        #expect(audio.lastPathComponent == "2026-10-07 09.00.00 Long Dictation.m4a")
        #expect(!FileManager.default.fileExists(atPath: recording.path))
        #expect(try Data(contentsOf: audio) == Data([1, 2, 3]))
        // Listed again from the folder, it still has its recording.
        store.load()
        #expect(store.transcripts.first?.audioURL == audio)
        try store.delete(saved)
        #expect(!FileManager.default.fileExists(atPath: audio.path))
        #expect(!FileManager.default.fileExists(atPath: saved.url.path))
    }

    @Test func aTranscriptWithoutARecordingHasNoAudio() throws {
        let store = makeStore()
        let saved = try store.save("x", title: "Live Transcription")
        #expect(saved.audioURL == nil)
    }

    @Test func deletingRemovesTheFileAndTheEntry() throws {
        let store = makeStore()
        let saved = try store.save("x", title: "Long Dictation")
        try store.delete(saved)
        #expect(store.transcripts.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: saved.url.path))
    }

    @Test func rowDatesSayTodayAndYesterday() {
        let now = date("2026-10-06 15:00:00")
        #expect(TranscriptsView.rowDate(date("2026-10-06 14:32:00"), now: now).hasPrefix("Today, "))
        #expect(TranscriptsView.rowDate(date("2026-10-05 23:10:00"), now: now).hasPrefix("Yesterday, "))
        #expect(!TranscriptsView.rowDate(date("2026-10-01 09:00:00"), now: now).hasPrefix("Today"))
        #expect(TranscriptsView.rowDate(date("2026-10-01 09:00:00"), now: now).contains("2026"))
    }
}
