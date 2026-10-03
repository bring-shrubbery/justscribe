//
//  DictationMode.swift
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

/// How dictated text is cleaned up for a set of apps.
nonisolated struct DictationMode: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    /// What the clean-up model is told to do; blank falls back to Default's.
    var instructions: String
    /// Off: the raw transcript (after commands and vocabulary) goes to these apps.
    var cleanUp: Bool
    var appBundleIDs: [String]

    static let defaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let defaultInstructions = "Fix grammar, spelling and punctuation. Preserve the meaning and tone."

    static func makeDefault() -> DictationMode {
        DictationMode(id: defaultID, name: "Default", instructions: defaultInstructions, cleanUp: true, appBundleIDs: [])
    }

    var isDefault: Bool { id == Self.defaultID }

    var effectiveInstructions: String {
        let trimmed = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultInstructions : trimmed
    }
}

nonisolated struct ModesFile: Codable, Equatable, Sendable {
    static let currentVersion = 1
    var version: Int
    var modes: [DictationMode]
}
