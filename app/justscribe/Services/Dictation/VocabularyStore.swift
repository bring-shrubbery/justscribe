//
//  VocabularyStore.swift
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

/// The user's vocabulary, newest first, in `vocabulary.json`.
@Observable
final class VocabularyStore {
    static let shared = VocabularyStore(fileURL: JSONFile.containerURL("vocabulary.json"))

    private(set) var entries: [VocabularyEntry] = []
    private(set) var fileWasSetAside = false
    private let fileURL: URL

    init(fileURL: URL) { self.fileURL = fileURL }

    func load() {
        switch JSONFile.read(VocabularyFile.self, from: fileURL) {
        case .missing: entries = []
        case .loaded(let file): entries = file.entries.sorted { $0.createdAt > $1.createdAt }
        case .damaged: JSONFile.setAside(fileURL); fileWasSetAside = true; entries = []
        }
    }

    func add(text: String, heardAs: [String]) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }
        let forms = Self.cleanForms(heardAs)
        entries.insert(VocabularyEntry(id: UUID(), text: cleanText, heardAs: forms, createdAt: Self.now()), at: 0)
        save()
    }

    func update(_ entry: VocabularyEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var entry = entry
        entry.text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.heardAs = Self.cleanForms(entry.heardAs)
        entries[index] = entry
        save()
    }

    func delete(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    /// One entry per non-empty line: `text` or `text = form, form`. Skips texts already present.
    /// Returns how many were added.
    @discardableResult
    func importLines(_ lines: String) -> Int {
        var added = 0
        let existing = Set(entries.map { $0.text.lowercased() })
        var seen = existing
        for line in lines.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let text = parts.first, !text.isEmpty, !seen.contains(text.lowercased()) else { continue }
            let forms = parts.count > 1 ? Self.cleanForms(parts[1].split(separator: ",").map(String.init)) : []
            entries.insert(VocabularyEntry(id: UUID(), text: text, heardAs: forms, createdAt: Self.now()), at: 0)
            seen.insert(text.lowercased())
            added += 1
        }
        if added > 0 { save() }
        return added
    }

    /// Whole seconds: ISO 8601 in the file keeps no fraction, so a finer date would not read
    /// back equal. Entries made in the same second keep their order (the sort on load is stable).
    private static func now() -> Date {
        Date(timeIntervalSinceReferenceDate: Date().timeIntervalSinceReferenceDate.rounded(.down))
    }

    private static func cleanForms(_ forms: [String]) -> [String] {
        forms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func save() {
        JSONFile.write(VocabularyFile(version: VocabularyFile.currentVersion, entries: entries), to: fileURL)
    }
}
