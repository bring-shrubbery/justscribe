//
//  DictationRecord.swift
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

/// One kept dictation: what the user got, when, and (optionally) the recording it came from.
nonisolated struct DictationRecord: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var createdAt: Date
    /// The final text, after grammar correction: the same text the user got.
    var text: String
    var durationSeconds: Double
    /// The unified model ID (`provider:variant`) that transcribed it.
    var modelID: String
    var language: String?
    /// The recording's file name in the audio folder, when it was kept and still exists.
    var audioFileName: String?
}

/// The on-disk index. `version` lets a later format change migrate.
nonisolated struct HistoryIndex: Codable, Equatable, Sendable {
    static let currentVersion = 1
    var version: Int
    var records: [DictationRecord]

    static let empty = HistoryIndex(version: currentVersion, records: [])
}
