//
//  DictionaryWords.swift
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

import AppKit

/// Whether a word is in the system dictionary for a language — the guard that keeps vocabulary
/// sound-alike matching away from ordinary words. Main actor: `NSSpellChecker` is AppKit.
enum DictionaryWords {
    private static var cache: [String: Bool] = [:]

    static func isWord(_ word: String, language: String?) -> Bool {
        let key = (language ?? "") + "|" + word.lowercased()
        if let cached = cache[key] { return cached }
        let checker = NSSpellChecker.shared
        let range = checker.checkSpelling(of: word, startingAt: 0, language: language, wrap: false,
                                          inSpellDocumentWithTag: 0, wordCount: nil)
        let result = range.location == NSNotFound
        if cache.count > 20_000 { cache.removeAll() }
        cache[key] = result
        return result
    }
}
