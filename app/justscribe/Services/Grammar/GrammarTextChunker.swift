//
//  GrammarTextChunker.swift
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

/// Splits text into chunks small enough for a model with a limited context window,
/// breaking on sentence boundaries where possible.
///
/// Invariant: `chunks(t).joined() == t` for every input. Whitespace between
/// sentences is carried inside whichever chunk it falls in, never dropped.
nonisolated enum GrammarTextChunker {

    static func chunks(_ text: String, maxLength: Int = 2000) -> [String] {
        guard !text.isEmpty else { return [] }
        guard text.count > maxLength else { return [text] }

        var result: [String] = []
        var current = ""

        for sentence in pieces(in: text, options: .bySentences) {
            if sentence.count > maxLength {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
                result.append(contentsOf: splitOnWords(sentence, maxLength: maxLength))
                continue
            }
            if !current.isEmpty && current.count + sentence.count > maxLength {
                result.append(current)
                current = sentence
            } else {
                current += sentence
            }
        }

        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Split a single oversized sentence on word boundaries. A word longer than
    /// `maxLength` is emitted as its own oversized chunk rather than broken mid-word.
    private static func splitOnWords(_ text: String, maxLength: Int) -> [String] {
        var result: [String] = []
        var current = ""
        for word in pieces(in: text, options: .byWords) {
            if !current.isEmpty && current.count + word.count > maxLength {
                result.append(current)
                current = word
            } else {
                current += word
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Enumerate substrings, emitting the gaps between them as their own pieces so
    /// that concatenating the result reproduces the input exactly.
    private static func pieces(in text: String, options: String.EnumerationOptions) -> [String] {
        var out: [String] = []
        var covered = text.startIndex
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: options) { _, range, _, _ in
            if covered < range.lowerBound {
                out.append(String(text[covered..<range.lowerBound]))
            }
            out.append(String(text[range]))
            covered = range.upperBound
        }
        if covered < text.endIndex {
            out.append(String(text[covered...]))
        }
        return out.isEmpty ? [text] : out
    }
}
