//
//  GrammarPrompt.swift
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

/// The system prompt both clean-up backends use: the mode's instructions inside a fixed frame
/// that keeps the model answering with text only.
nonisolated enum GrammarPrompt {
    static let contract = "Apply this to the text that follows. Output only the resulting text: no explanations, no quotes, no preamble."

    static func frame(_ instructions: String) -> String {
        let trimmed = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmed.isEmpty ? DictationMode.defaultInstructions : trimmed
        return body + "\n\n" + contract
    }
}
