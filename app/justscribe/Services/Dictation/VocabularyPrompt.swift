//
//  VocabularyPrompt.swift
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

/// The vocabulary as Whisper's initial prompt: the words the user wants, newest first.
nonisolated enum VocabularyPrompt {
    static func text(_ entries: [VocabularyEntry]) -> String {
        entries.sorted { $0.createdAt > $1.createdAt }.map(\.text).joined(separator: " ")
    }
}
