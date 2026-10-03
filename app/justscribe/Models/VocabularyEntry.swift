//
//  VocabularyEntry.swift
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

/// A word or phrase the user wants spelled exactly so, with the ways the model tends to hear it.
nonisolated struct VocabularyEntry: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    /// Inserted exactly as written.
    var text: String
    /// Phrases that always become `text` (case-insensitive, spacing and hyphens ignored).
    var heardAs: [String]
    var createdAt: Date
}

/// The on-disk list. `version` lets a later format change migrate.
nonisolated struct VocabularyFile: Codable, Equatable, Sendable {
    static let currentVersion = 1
    var version: Int
    var entries: [VocabularyEntry]
    static let empty = VocabularyFile(version: currentVersion, entries: [])
}
