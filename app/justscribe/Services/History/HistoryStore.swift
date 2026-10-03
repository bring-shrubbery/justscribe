//
//  HistoryStore.swift
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
import Observation

/// The kept dictations: an index file and a folder of recordings inside the app's container.
/// Nothing is written unless `add` is called, which only happens when a history switch is on.
@Observable
final class HistoryStore {
    static let audioCap = 1_000_000_000

    static let shared = HistoryStore(directory: defaultDirectory())

    /// Newest first.
    private(set) var records: [DictationRecord] = []
    /// The audio folder's total size in bytes.
    private(set) var audioBytes = 0
    /// True when `load` found an index it could not read and renamed it `index.json.broken`.
    private(set) var indexWasSetAside = false

    private let directory: URL
    private let audioCap: Int
    private var indexURL: URL { directory.appendingPathComponent("index.json") }
    private var audioDirectory: URL { directory.appendingPathComponent("audio") }
    /// Additions run one after another so two in flight cannot interleave their index writes.
    private var pending: Task<Void, Never>?

    init(directory: URL, audioCap: Int = HistoryStore.audioCap) {
        self.directory = directory
        self.audioCap = audioCap
    }

    static func defaultDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "com.quassum.justscribe"
        return support.appendingPathComponent(bundleID).appendingPathComponent("History")
    }

    // MARK: - Loading

    func load() {
        let fm = FileManager.default
        try? fm.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        var loaded = HistoryIndex.empty
        if let data = try? Data(contentsOf: indexURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let index = try? decoder.decode(HistoryIndex.self, from: data) {
                loaded = index
            } else {
                let broken = directory.appendingPathComponent("index.json.broken")
                try? fm.removeItem(at: broken)
                try? fm.moveItem(at: indexURL, to: broken)
                indexWasSetAside = true
            }
        }
        // Audio files no record names are leftovers; records naming a missing file lose it.
        let present = Set((try? fm.contentsOfDirectory(atPath: audioDirectory.path)) ?? [])
        let named = Set(loaded.records.compactMap(\.audioFileName))
        for orphan in present.subtracting(named) {
            try? fm.removeItem(at: audioDirectory.appendingPathComponent(orphan))
        }
        records = loaded.records
            .map { record in
                var record = record
                if let name = record.audioFileName, !present.contains(name) { record.audioFileName = nil }
                return record
            }
            .sorted { $0.createdAt > $1.createdAt }
        audioBytes = totalAudioBytes()
    }

    // MARK: - Adding

    /// Keeps one dictation. The audio (if any) is encoded off the main actor and written before
    /// the record is added, so the index never names a file that does not exist.
    func add(text: String, durationSeconds: Double, modelID: String, language: String?, audio: [Float]?) async {
        let previous = pending
        let task = Task { [weak self] in
            _ = await previous?.value
            await self?.addNow(text: text, durationSeconds: durationSeconds, modelID: modelID, language: language, audio: audio)
        }
        pending = task
        await task.value
    }

    private func addNow(text: String, durationSeconds: Double, modelID: String, language: String?, audio: [Float]?) async {
        // ISO 8601 in the index keeps whole seconds; keep the same in memory so a reload matches.
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        var record = DictationRecord(
            id: UUID(), createdAt: now, text: text, durationSeconds: durationSeconds,
            modelID: modelID, language: language, audioFileName: nil)
        if let audio, !audio.isEmpty {
            let name = "\(record.id.uuidString).m4a"
            let url = audioDirectory.appendingPathComponent(name)
            do {
                try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
                try await HistoryAudioWriter.write(samples: audio, to: url)
                record.audioFileName = name
            } catch {
                print("History: audio not kept: \(error)")
            }
        }
        records.insert(record, at: 0)
        if !saveIndex() {
            // Disk and memory must agree: undo the addition, and drop its audio.
            records.removeFirst()
            if let name = record.audioFileName {
                try? FileManager.default.removeItem(at: audioDirectory.appendingPathComponent(name))
            }
            return
        }
        audioBytes = totalAudioBytes()
        enforceCap()
    }

    // MARK: - Removing

    func delete(_ id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let record = records.remove(at: index)
        if let name = record.audioFileName {
            try? FileManager.default.removeItem(at: audioDirectory.appendingPathComponent(name))
        }
        _ = saveIndex()
        audioBytes = totalAudioBytes()
    }

    func deleteAll() {
        records = []
        try? FileManager.default.removeItem(at: audioDirectory)
        try? FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        _ = saveIndex()
        audioBytes = 0
    }

    // MARK: - Reading

    func search(_ query: String) -> [DictationRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return records }
        return records.filter { Self.matches($0.text, query: trimmed) }
    }

    /// Case- and diacritic-insensitive containment, in the user's locale.
    nonisolated static func matches(_ text: String, query: String) -> Bool {
        text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], locale: .current) != nil
    }

    func audioURL(for record: DictationRecord) -> URL? {
        guard let name = record.audioFileName else { return nil }
        let url = audioDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - The cap

    /// The audio files to remove, oldest first, until the total is within the cap.
    /// `records` is newest first; `sizes` maps file names to byte counts.
    nonisolated static func audioToRemove(records: [DictationRecord], sizes: [String: Int], cap: Int) -> [String] {
        var total = sizes.values.reduce(0, +)
        var removed: [String] = []
        for record in records.reversed() {
            guard total > cap, let name = record.audioFileName, let size = sizes[name] else { continue }
            removed.append(name)
            total -= size
        }
        return removed
    }

    private func enforceCap() {
        let doomed = Set(Self.audioToRemove(records: records, sizes: audioSizes(), cap: audioCap))
        guard !doomed.isEmpty else { return }
        for name in doomed {
            try? FileManager.default.removeItem(at: audioDirectory.appendingPathComponent(name))
        }
        records = records.map { record in
            var record = record
            if let name = record.audioFileName, doomed.contains(name) { record.audioFileName = nil }
            return record
        }
        _ = saveIndex()
        audioBytes = totalAudioBytes()
    }

    // MARK: - Files

    private func audioSizes() -> [String: Int] {
        let fm = FileManager.default
        var sizes: [String: Int] = [:]
        for name in (try? fm.contentsOfDirectory(atPath: audioDirectory.path)) ?? [] {
            let path = audioDirectory.appendingPathComponent(name).path
            sizes[name] = (try? fm.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        }
        return sizes
    }

    private func totalAudioBytes() -> Int {
        audioSizes().values.reduce(0, +)
    }

    /// Atomic; false when the index could not be written.
    private func saveIndex() -> Bool {
        let index = HistoryIndex(version: HistoryIndex.currentVersion, records: records)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoder.encode(index).write(to: indexURL, options: .atomic)
            return true
        } catch {
            print("History: index not saved: \(error)")
            return false
        }
    }
}
