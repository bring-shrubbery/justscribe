//
//  SuggestionRanker.swift
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

/// Picks the three suggestions above the keys, and the one applied on space,
/// from what the system spell checker says about the word being typed.
///
/// Pure, so it is tested without a spell checker: `TextCheckerAutocompleteService`
/// in the keyboard feeds it.
nonisolated enum SuggestionRanker {

    struct Suggestion: Equatable, Sendable {
        let text: String
        /// Replaces the typed word when the user types a space or punctuation.
        var isAutocorrect = false
        /// The word as typed, shown in quotes because something else will replace it.
        var isVerbatim = false
    }

    /// What the spell checker knows about the word being typed.
    struct Input: Sendable {
        var word: String
        var isMisspelled: Bool
        /// Corrections, best first.
        var guesses: [String] = []
        /// Words that start with `word`, most likely first.
        var completions: [String] = []
        /// The user's text replacements (Settings › General › Keyboard), shortcut → phrase.
        var replacements: [String: String] = [:]
        /// How common a word is, 0 for the most common; nil when unknown.
        var rank: @Sendable (String) -> Int? = { _ in nil }
    }

    static func suggestions(for input: Input) -> [Suggestion] {
        let word = input.word
        guard !word.isEmpty else { return [] }

        if let phrase = replacement(for: word, in: input.replacements) {
            return [Suggestion(text: word, isVerbatim: true), Suggestion(text: phrase, isAutocorrect: true)]
        }
        if let fixed = fixedForm(of: word) {
            return [Suggestion(text: word, isVerbatim: true), Suggestion(text: fixed, isAutocorrect: true)]
        }

        let completions = input.completions
            .filter { $0.caseInsensitiveCompare(word) != .orderedSame }
            .map { matchingCase(of: word, $0) }

        guard input.isMisspelled else {
            return [Suggestion(text: word)] + completions.prefix(2).map { Suggestion(text: $0) }
        }

        let guesses = input.guesses.map { matchingCase(of: word, $0) }
        // Still typing a word that has completions: suggest them, correct nothing.
        let isPartialWord = !completions.isEmpty && word.count <= 3
        let correction = isPartialWord ? nil : bestCorrection(of: word, among: guesses, rank: input.rank)

        var result = [Suggestion(text: word, isVerbatim: correction != nil)]
        if let correction {
            result.append(Suggestion(text: correction, isAutocorrect: true))
        }
        for candidate in completions + guesses where result.count < 3 {
            if !result.contains(where: { $0.text.caseInsensitiveCompare(candidate) == .orderedSame }) {
                result.append(Suggestion(text: candidate))
            }
        }
        return result
    }

    /// The guess one typo away that the user most likely meant. A missed or swapped
    /// letter is likelier than a wrong one ("Helo" is "Hello", not "Help"), and a
    /// common word likelier than a rare one. Words the frequency list does not know
    /// are only considered when it knows none of them.
    static func bestCorrection(
        of word: String,
        among guesses: [String],
        rank: (String) -> Int?
    ) -> String? {
        let typed = word.lowercased()
        let close = guesses.enumerated().filter { editDistance(typed, $0.element.lowercased()) <= 1 }
        let ranked = close.filter { rank($0.element) != nil }
        let candidates = ranked.isEmpty ? close : ranked
        return candidates.min { a, b in
            let kindA = editKind(from: typed, to: a.element.lowercased())
            let kindB = editKind(from: typed, to: b.element.lowercased())
            if kindA != kindB { return kindA < kindB }
            let rankA = rank(a.element) ?? .max, rankB = rank(b.element) ?? .max
            if rankA != rankB { return rankA < rankB }
            return a.offset < b.offset
        }?.element
    }

    /// 0 for a missed or swapped letter, 1 for a wrong or extra one.
    private static func editKind(from typed: String, to candidate: String) -> Int {
        if candidate.count > typed.count { return 0 }
        if candidate.count == typed.count, candidate.sorted() == typed.sorted() { return 0 }
        return 1
    }

    /// The word being typed: the letters and apostrophes after the last space or punctuation.
    static func currentWord(in text: String) -> String {
        String(text.reversed().prefix { $0.isLetter || $0 == "'" || $0 == "’" }.reversed())
    }

    /// Keeps a capital the user typed: "Hel" completes to "Hello", not "hello".
    static func matchingCase(of typed: String, _ candidate: String) -> String {
        guard let first = typed.first, first.isUppercase else { return candidate }
        return candidate.prefix(1).uppercased() + candidate.dropFirst()
    }

    private static func replacement(for word: String, in replacements: [String: String]) -> String? {
        replacements.first { $0.key.caseInsensitiveCompare(word) == .orderedSame }?.value
    }

    /// Words the spell checker accepts or misses that the system keyboard always fixes.
    private static func fixedForm(of word: String) -> String? {
        guard let fixed = fixes[word.lowercased()] else { return nil }
        let result = matchingCase(of: word, fixed)
        return result == word ? nil : result
    }

    private static let fixes: [String: String] = [
        "i": "I", "im": "I'm", "ive": "I've",
        "dont": "don't", "doesnt": "doesn't", "didnt": "didn't",
        "cant": "can't", "couldnt": "couldn't", "wont": "won't", "wouldnt": "wouldn't",
        "shouldnt": "shouldn't", "isnt": "isn't", "arent": "aren't", "wasnt": "wasn't",
        "werent": "weren't", "hasnt": "hasn't", "havent": "haven't", "hadnt": "hadn't",
        "youre": "you're", "youve": "you've", "theyre": "they're", "theyve": "they've",
        "thats": "that's", "whats": "what's", "theres": "there's", "heres": "here's",
        "wouldve": "would've", "couldve": "could've", "shouldve": "should've",
        "alot": "a lot",
    ]

    /// Edits between two words, a swap of neighbouring letters counting as one
    /// ("teh" → "the"): what "one typo away" means for autocorrection.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[a.count][b.count]
    }
}
