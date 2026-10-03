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

    /// Levenshtein distance.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
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
    static func apply(words: [String], entries: [VocabularyEntry], isDictionaryWord: (String) -> Bool) -> [String] {
        guard !words.isEmpty, !entries.isEmpty else { return words }
        var tokens = words.map(Token.init)
        var locked = [Bool](repeating: false, count: tokens.count)
        let maxRun = 4

        // 1. Explicit forms, longest runs first so "swift ui" beats "ui".
        for run in stride(from: maxRun, through: 1, by: -1) {
            for entry in entries {
                let forms = entry.heardAs.map(key).filter { !$0.isEmpty }
                guard !forms.isEmpty else { continue }
                replaceRuns(of: run, in: &tokens, locked: &locked, with: entry.text) { runKey, _ in forms.contains(runKey) }
            }
        }
        // 2. Sound-alikes: runs of the entry's own word count, containing a non-dictionary word.
        for entry in entries {
            let entryWords = entry.text.split(whereSeparator: \.isWhitespace).map { key(String($0)) }.filter { !$0.isEmpty }
            guard !entryWords.isEmpty else { continue }
            let entryKey = entryWords.joined()
            let bound = entryKey.count <= 5 ? 1 : 2
            let entryPhonetic = phoneticKey(entryKey)
            replaceRuns(of: entryWords.count, in: &tokens, locked: &locked, with: entry.text) { runKey, runCores in
                guard runKey != entryKey else { return true }   // already right: keeps the pass idempotent
                guard runCores.contains(where: { !isDictionaryWord($0) }) else { return false }
                return editDistance(runKey, entryKey) <= bound || (!entryPhonetic.isEmpty && phoneticKey(runKey) == entryPhonetic)
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

    private struct Token {
        var leading: String
        var core: String
        var trailing: String
        init(_ s: String) {
            let coreStart = s.firstIndex(where: { $0.isLetter || $0.isNumber }) ?? s.endIndex
            let coreEnd = s.lastIndex(where: { $0.isLetter || $0.isNumber }).map { s.index(after: $0) } ?? coreStart
            leading = String(s[..<coreStart]); core = String(s[coreStart..<coreEnd]); trailing = String(s[coreEnd...])
        }
        var text: String { leading + core + trailing }
    }

    private static func replaceRuns(
        of length: Int, in tokens: inout [Token], locked: inout [Bool], with replacement: String,
        where matches: (_ runKey: String, _ runCores: [String]) -> Bool
    ) {
        guard length >= 1, tokens.count >= length else { return }
        var i = 0
        while i + length <= tokens.count {
            let range = i..<(i + length)
            let cores = range.map { tokens[$0].core }
            if !range.contains(where: { locked[$0] }), !cores.contains(where: \.isEmpty), matches(cores.map(key).joined(), cores) {
                var first = tokens[range.lowerBound]
                first.core = replacement
                first.trailing = tokens[range.upperBound - 1].trailing
                tokens[range.lowerBound] = first
                for j in range.dropFirst() { tokens[j] = Token(""); locked[j] = true }
                locked[range.lowerBound] = true
                i += length
            } else {
                i += 1
            }
        }
    }
}
