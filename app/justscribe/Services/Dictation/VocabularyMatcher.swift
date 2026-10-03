//
//  VocabularyMatcher.swift
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

/// Puts the user's vocabulary into a transcript: explicit "heard as" forms first, then words the
/// model got wrong by sound or spelling. Pure; the dictionary check is injected.
nonisolated enum VocabularyMatcher {

    /// Letters and digits of a word, lower-cased, without diacritics, spaces or hyphens.
    static func key(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// Levenshtein distance. With a `limit`, strings whose lengths differ by more than it return
    /// `limit + 1` at once, without the full table.
    static func editDistance(_ a: String, _ b: String, limit: Int? = nil) -> Int {
        let a = Array(a), b = Array(b)
        if let limit, abs(a.count - b.count) > limit { return limit + 1 }
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    /// Metaphone-style phonetic key: words that sound alike share it.
    static func phoneticKey(_ word: String) -> String {
        var s = Array(key(word).filter { $0.isLetter })
        guard !s.isEmpty else { return "" }
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        // Silent initial pairs, and an initial "x" that sounds like "s".
        if s.count > 1 {
            let head = String(s[0...1])
            if ["kn", "gn", "pn", "ae", "wr"].contains(head) { s.removeFirst() }
            else if head == "wh" { s[1] = "w"; s.removeFirst() }
        }
        if s.first == "x" { s[0] = "s" }

        var out = ""
        func at(_ i: Int) -> Character? { i >= 0 && i < s.count ? s[i] : nil }
        func isVowel(_ c: Character?) -> Bool { c.map { vowels.contains($0) } ?? false }
        var i = 0
        while i < s.count {
            let c = s[i]
            defer { i += 1 }
            if c != "c", at(i - 1) == c { continue }           // doubled letters, except "cc"
            switch c {
            case "a", "e", "i", "o", "u", "y":
                if i == 0 { out += "a" }
            case "b":
                if !(i == s.count - 1 && at(i - 1) == "m") { out += "b" }
            case "c":
                if at(i + 1) == "i", at(i + 2) == "a" { out += "x" }
                else if at(i + 1) == "h" {
                    // "sch", "chr", "chl" sound like k (Christine); other "ch" like sh (Charles → x).
                    out += (at(i - 1) == "s" || ["r", "l"].contains(at(i + 2) ?? " ")) ? "k" : "x"; i += 1
                }
                else if ["i", "e", "y"].contains(at(i + 1) ?? " ") { out += "s" }
                else { out += "k" }
            case "d":
                if at(i + 1) == "g", ["e", "y", "i"].contains(at(i + 2) ?? " ") { out += "j"; i += 2 } else { out += "t" }
            case "g":
                if at(i + 1) == "h", !isVowel(at(i + 2)) { continue }
                if at(i + 1) == "n", i + 1 == s.count - 1 || (at(i + 2) == "e" && at(i + 3) == "d") { continue }
                if ["i", "e", "y"].contains(at(i + 1) ?? " ") { out += "j" } else { out += "k" }
            case "h":
                if isVowel(at(i - 1)), !isVowel(at(i + 1)) { continue }
                if ["c", "s", "p", "t", "g"].contains(at(i - 1) ?? " ") { continue }
                out += "h"
            case "k":
                if at(i - 1) != "c" { out += "k" }
            case "p":
                if at(i + 1) == "h" { out += "f"; i += 1 } else { out += "p" }
            case "q": out += "k"
            case "s":
                if at(i + 1) == "h" { out += "x"; i += 1 }
                else if at(i + 1) == "i", ["o", "a"].contains(at(i + 2) ?? " ") { out += "x" }
                else { out += "s" }
            case "t":
                if at(i + 1) == "i", ["o", "a"].contains(at(i + 2) ?? " ") { out += "x" }
                else if at(i + 1) == "h" { out += "0"; i += 1 }
                else if !(at(i + 1) == "c" && at(i + 2) == "h") { out += "t" }
            case "v": out += "f"
            case "w", "j":
                if c == "j" { out += "j" } else if isVowel(at(i + 1)) { out += "w" }
            case "x": out += "ks"
            case "z": out += "s"
            default: out += String(c)
            }
        }
        return out
    }

    // MARK: - Applying

    /// `words` as the model produced them (each may carry its own spaces and punctuation).
    /// Returns the same number of strings; a run that became one entry keeps its text in the
    /// first word and `""` in the rest, so callers can merge times.
    ///
    /// Three passes, each locking what it replaced: explicit "heard as" forms, then exact
    /// spellings of an entry, then sound-alikes. A run never crosses clause punctuation, and
    /// exact and sound-alike matches need a word the dictionary does not know.
    static func apply(words: [String], entries: [VocabularyEntry], isDictionaryWord: (String) -> Bool) -> [String] {
        guard !words.isEmpty, !entries.isEmpty else { return words }
        var tokens = words.map(Token.init)
        // Keys without and with a possessive "'s" ("mcdonald" / "mcdonalds"); equal for most words.
        var keys = tokens.map { key($0.core) }
        var fullKeys = tokens.map { key($0.core + $0.possessive) }
        var locked = [Bool](repeating: false, count: tokens.count)
        let prepared = entries.map(PreparedEntry.init)
        let maxRun = 4

        // A slot is only ever looked up while unlocked, and unlocked slots are never rewritten,
        // so the original cores are the ones to ask about, each at most once.
        let cores = tokens.map(\.core)
        var knownWord = [Bool?](repeating: nil, count: tokens.count)
        func hasNonDictionaryWord(_ range: Range<Int>) -> Bool {
            for i in range {
                let isWord: Bool
                if let known = knownWord[i] { isWord = known } else { isWord = isDictionaryWord(cores[i]); knownWord[i] = isWord }
                if !isWord { return true }
            }
            return false
        }
        var phoneticMemo: [String: String] = [:]
        func phonetic(_ runKey: String) -> String {
            if let known = phoneticMemo[runKey] { return known }
            let value = phoneticKey(runKey)
            phoneticMemo[runKey] = value
            return value
        }

        // 1. Explicit forms, longest runs first so "swift ui" beats "ui".
        for run in stride(from: maxRun, through: 1, by: -1) {
            for entry in prepared where !entry.forms.isEmpty {
                replaceRuns(of: run, in: &tokens, keys: &keys, fullKeys: &fullKeys, locked: &locked, with: entry.text) { runKey, _ in
                    entry.forms.contains(runKey)
                }
            }
        }
        // 2. Exact spellings, longest entries first, so a correct word is never taken by a
        //    neighbouring entry's sound-alike. Dictionary words keep their own casing.
        let byLength = prepared.indices.sorted { (prepared[$0].wordCount, -$0) > (prepared[$1].wordCount, -$1) }.map { prepared[$0] }
        for entry in byLength where entry.wordCount > 0 {
            replaceRuns(of: entry.wordCount, in: &tokens, keys: &keys, fullKeys: &fullKeys, locked: &locked, with: entry.text) { runKey, range in
                runKey == entry.key && hasNonDictionaryWord(range)
            }
        }
        // 3. Sound-alikes: runs of the entry's own word count, containing a non-dictionary word.
        for entry in prepared where entry.wordCount > 0 && entry.allowsSoundAlike {
            // "antony's" must be heard as "antony" + "'s", not as a word two letters from Antoni;
            // only an entry that itself ends in "'s" is compared with the suffix put back.
            replaceRuns(
                of: entry.wordCount, in: &tokens, keys: &keys, fullKeys: &fullKeys, locked: &locked,
                with: entry.text, triesPossessive: entry.endsInPossessive
            ) { runKey, range in
                guard runKey != entry.key else { return false }   // a dictionary word spelled like the entry
                if !entry.digits.isEmpty, digits(of: runKey) != entry.digits { return false }
                let close = editDistance(runKey, entry.key, limit: entry.bound) <= entry.bound
                guard close || (!entry.phonetic.isEmpty && phonetic(runKey) == entry.phonetic) else { return false }
                return hasNonDictionaryWord(range)
            }
        }
        return tokens.map(\.text)
    }

    /// Free text: words keep their punctuation, and the whitespace between them (spaces, line
    /// breaks) is kept as it was; an absorbed word takes the whitespace before it with it.
    static func apply(_ text: String, entries: [VocabularyEntry], isDictionaryWord: (String) -> Bool) -> String {
        guard !text.isEmpty, !entries.isEmpty else { return text }
        var words: [String] = [], separators: [String] = []   // separators[i] precedes words[i]
        var word = "", gap = "", inWord = false
        for ch in text {
            if ch.isWhitespace {
                if inWord { words.append(word); word = ""; inWord = false }
                gap.append(ch)
            } else {
                if !inWord { separators.append(gap); gap = ""; inWord = true }
                word.append(ch)
            }
        }
        if inWord { words.append(word) }
        let fixed = apply(words: words, entries: entries, isDictionaryWord: isDictionaryWord)
        var result = ""
        for i in words.indices where !(fixed[i].isEmpty && !words[i].isEmpty) {
            result += separators[i] + fixed[i]
        }
        return result + gap
    }

    // MARK: - Private

    private static func digits(of key: String) -> String { key.filter(\.isNumber) }

    /// An entry with everything the passes compare against worked out once.
    private struct PreparedEntry {
        let text: String
        let forms: Set<String>
        let key: String
        let wordCount: Int
        let digits: String
        let bound: Int
        /// Keys under three letters ("AI") would match half the language by sound.
        let allowsSoundAlike: Bool
        /// Empty when too short to tell words apart.
        let phonetic: String
        /// "McDonald's": a run's own "'s" is part of the match, not something to add after it.
        let endsInPossessive: Bool

        init(_ entry: VocabularyEntry) {
            text = entry.text
            forms = Set(entry.heardAs.map(VocabularyMatcher.key).filter { !$0.isEmpty })
            let words = entry.text.split(whereSeparator: \.isWhitespace).map { VocabularyMatcher.key(String($0)) }.filter { !$0.isEmpty }
            key = words.joined()
            wordCount = words.count
            digits = VocabularyMatcher.digits(of: key)
            bound = key.count <= 5 ? 1 : 2
            allowsSoundAlike = key.count >= 3
            let p = VocabularyMatcher.phoneticKey(key)
            phonetic = p.count >= 2 ? p : ""
            endsInPossessive = VocabularyMatcher.possessiveSuffixes.contains { entry.text.hasSuffix($0) }
        }
    }

    private static let possessiveSuffixes = ["'s", "\u{2019}s", "'S", "\u{2019}S"]

    private struct Token {
        var leading: String
        var core: String
        /// A possessive "'s" split off the word, so a replacement keeps it ("Antoni's").
        var possessive: String
        var trailing: String
        init(_ s: String) {
            let coreStart = s.firstIndex(where: { $0.isLetter || $0.isNumber }) ?? s.endIndex
            var coreEnd = s.lastIndex(where: { $0.isLetter || $0.isNumber }).map { s.index(after: $0) } ?? coreStart
            // A possessive "'s" is not part of the word: it stays after the replacement.
            let core = s[coreStart..<coreEnd]
            for suffix in VocabularyMatcher.possessiveSuffixes where core.count > suffix.count && core.hasSuffix(suffix) {
                coreEnd = s.index(coreEnd, offsetBy: -suffix.count)
                break
            }
            let wordEnd = s.lastIndex(where: { $0.isLetter || $0.isNumber }).map { s.index(after: $0) } ?? coreStart
            leading = String(s[..<coreStart]); self.core = String(s[coreStart..<coreEnd])
            possessive = String(s[coreEnd..<wordEnd]); trailing = String(s[wordEnd...])
        }
        var text: String { leading + core + possessive + trailing }
    }

    private static let clauseBreaks: Set<Character> = [".", "?", "!", ",", ";", ":"]

    /// Replaces each unlocked run of `length` tokens that `matches` accepts. With `triesPossessive`,
    /// a run ending in "'s" is offered first with the suffix as part of its key, and a match that
    /// way takes the suffix into the replacement; so does a replacement that already ends in "'s".
    private static func replaceRuns(
        of length: Int, in tokens: inout [Token], keys: inout [String], fullKeys: inout [String], locked: inout [Bool],
        with replacement: String, triesPossessive: Bool = true,
        where matches: (_ runKey: String, _ range: Range<Int>) -> Bool
    ) {
        guard length >= 1, tokens.count >= length else { return }
        let replacementKey = key(replacement)
        let replacementEndsInPossessive = possessiveSuffixes.contains { replacement.hasSuffix($0) }
        var i = 0
        while i + length <= tokens.count {
            let range = i..<(i + length)
            guard !range.contains(where: { locked[$0] || tokens[$0].core.isEmpty }),
                  !range.dropLast().contains(where: { tokens[$0].trailing.contains(where: clauseBreaks.contains) })
            else { i += 1; continue }
            let last = tokens[range.upperBound - 1]
            let bareKey = range.map { keys[$0] }.joined()
            let fullKey = range.map { fullKeys[$0] }.joined()
            let matchedWithSuffix = triesPossessive && fullKey != bareKey && matches(fullKey, range)
            guard matchedWithSuffix || matches(bareKey, range) else { i += 1; continue }

            var first = tokens[range.lowerBound]
            first.core = replacement
            first.possessive = matchedWithSuffix || replacementEndsInPossessive ? "" : last.possessive
            first.trailing = last.trailing
            tokens[range.lowerBound] = first
            keys[range.lowerBound] = replacementKey
            fullKeys[range.lowerBound] = replacementKey
            for j in range.dropFirst() { tokens[j] = Token(""); keys[j] = ""; fullKeys[j] = ""; locked[j] = true }
            locked[range.lowerBound] = true
            i += length
        }
    }
}
