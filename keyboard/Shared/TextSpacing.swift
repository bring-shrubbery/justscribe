//
//  TextSpacing.swift
//  JustScribeKeyboard
//
//  Created by Antoni Silvestrovic on 22/10/2026.
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

nonisolated enum TextSpacing {

    /// The text to insert for a dictation so it reads on from what is already
    /// there: a space after a word or punctuation, none at the start of a field
    /// or a line, or after a space.
    static func insertion(of text: String, after before: String?) -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        guard let last = before?.last, !last.isWhitespace, !last.isNewline else { return text }
        if let first = text.first, ",.;:!?)".contains(first) { return text }
        return " " + text
    }
}
