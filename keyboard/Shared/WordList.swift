//
//  WordList.swift
//  JustScribeKeyboard
//
//  Created by Antoni Silvestrovic on 27/10/2026.
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

/// Words of one language, most common first, for completions and for ranking
/// corrections. The system spell checker offers no completions inside a keyboard
/// extension, so the keyboard brings its own list (`Keyboard/Resources/words-en.txt`).
nonisolated final class WordList: Sendable {

    private let ranks: [String: Int]
    private let alphabetical: [String]

    /// `words` in order of frequency, most common first, lowercased.
    init(wordsByFrequency words: [String]) {
        var ranks: [String: Int] = [:]
        ranks.reserveCapacity(words.count)
        for (rank, word) in words.enumerated() where ranks[word] == nil {
            ranks[word] = rank
        }
        self.ranks = ranks
        self.alphabetical = ranks.keys.sorted()
    }

    /// Reads a list with one word per line, most common first.
    convenience init?(contentsOf url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        self.init(wordsByFrequency: text.split(separator: "\n").map { String($0) })
    }

    /// 0 for the most common word; nil for a word not in the list.
    func rank(of word: String) -> Int? {
        ranks[word.lowercased()]
    }

    func contains(_ word: String) -> Bool {
        rank(of: word) != nil
    }

    /// Words that start with `prefix` and are longer, most common first.
    func completions(of prefix: String, limit: Int = 3) -> [String] {
        let prefix = prefix.lowercased()
        guard !prefix.isEmpty else { return [] }
        var low = 0, high = alphabetical.count
        while low < high {
            let mid = (low + high) / 2
            if alphabetical[mid] < prefix { low = mid + 1 } else { high = mid }
        }
        var matches: [String] = []
        var index = low
        while index < alphabetical.count, alphabetical[index].hasPrefix(prefix) {
            if alphabetical[index] != prefix { matches.append(alphabetical[index]) }
            index += 1
        }
        return Array(matches.sorted { ranks[$0, default: .max] < ranks[$1, default: .max] }.prefix(limit))
    }
}
