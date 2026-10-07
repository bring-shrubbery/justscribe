//
//  TranscriptStore.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 05/10/2026.
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

import AppKit
import Foundation
import Observation

/// One saved transcript: a text file in the Transcripts folder.
struct SavedTranscript: Identifiable, Equatable, Hashable {
    let url: URL
    let date: Date
    let title: String
    var id: URL { url }
}

/// The transcripts the app has written: long dictations, live transcriptions and transcribed
/// files, each a plain-text file with timestamps and speaker labels in
/// `Application Support/<bundle id>/Transcripts/`, named by when it was made and what it is.
/// The folder is the index: anything a user drops in shows up too.
@Observable
final class TranscriptStore {
    static let shared = TranscriptStore(directory: TranscriptStore.defaultDirectory())

    /// Newest first.
    private(set) var transcripts: [SavedTranscript] = []
    /// The transcript the Transcripts window should show next, set when something asks for a
    /// particular one (a click on the "Saved" indicator); the window selects it and clears it.
    var requestedSelection: URL?
    let directory: URL
    private let remove: (URL) throws -> Void

    /// `remove` deletes a transcript's file; the app moves it to the Trash.
    init(directory: URL, remove: @escaping (URL) throws -> Void = TranscriptStore.trash) {
        self.directory = directory
        self.remove = remove
    }

    static func defaultDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "com.quassum.justscribe"
        return support.appendingPathComponent(bundleID).appendingPathComponent("Transcripts")
    }

    static func trash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    // MARK: - Names

    private static let nameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }()

    /// "2026-10-06 14.32.05 Long Dictation.txt". The title loses the characters a file name
    /// cannot hold.
    nonisolated static func fileName(title: String, date: Date) -> String {
        var clean = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { clean = "Transcript" }
        return "\(nameFormatter.string(from: date)) \(clean).txt"
    }

    /// The date and title a file name made by `fileName` holds; nil for any other name.
    nonisolated static func parse(fileName: String) -> (date: Date, title: String)? {
        guard fileName.hasSuffix(".txt"), fileName.count > 24 else { return nil }
        let stem = String(fileName.dropLast(4))
        let stamp = String(stem.prefix(19))
        guard stem.count > 20, stem[stem.index(stem.startIndex, offsetBy: 19)] == " ",
              let date = nameFormatter.date(from: stamp) else { return nil }
        let title = String(stem.dropFirst(20))
        return title.isEmpty ? nil : (date, title)
    }

    // MARK: - Loading

    /// Reads the folder; files not named by the app are listed by their creation date.
    func load() {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let urls = (try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])) ?? []
        transcripts = urls
            .filter { $0.pathExtension.lowercased() == "txt" }
            .map { url in
                if let parsed = Self.parse(fileName: url.lastPathComponent) {
                    return SavedTranscript(url: url, date: parsed.date, title: parsed.title)
                }
                let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return SavedTranscript(url: url, date: created, title: url.deletingPathExtension().lastPathComponent)
            }
            .sorted { ($0.date, $0.url.lastPathComponent) > ($1.date, $1.url.lastPathComponent) }
    }

    // MARK: - Writing, reading, deleting

    /// Writes `text` as a new transcript and lists it. A name already taken gets a counter.
    @discardableResult
    func save(_ text: String, title: String, date: Date = Date()) throws -> SavedTranscript {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = Self.fileName(title: title, date: date)
        var url = directory.appendingPathComponent(name)
        var counter = 2
        while fm.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent(Self.fileName(title: "\(title) \(counter)", date: date))
            counter += 1
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
        load()
        return transcripts.first { $0.url == url } ?? SavedTranscript(url: url, date: date, title: title)
    }

    func text(of transcript: SavedTranscript) throws -> String {
        try String(contentsOf: transcript.url, encoding: .utf8)
    }

    func delete(_ transcript: SavedTranscript) throws {
        try remove(transcript.url)
        load()
    }

    func revealInFinder(_ transcript: SavedTranscript) {
        NSWorkspace.shared.activateFileViewerSelecting([transcript.url])
    }

    func openFolder() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }
}
