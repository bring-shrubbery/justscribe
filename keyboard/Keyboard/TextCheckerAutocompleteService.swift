//
//  TextCheckerAutocompleteService.swift
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

import KeyboardCore
import UIKit

/// Suggestions from the system spell checker: the word as typed, then
/// corrections when it is misspelled or completions when it is not. The first
/// correction is applied on space, as the system keyboard does.
nonisolated final class TextCheckerAutocompleteService: AutocompleteService {

    var locale: Locale

    init(locale: Locale) {
        self.locale = locale
    }

    func autocomplete(_ text: String) async throws -> Autocomplete.ServiceResult {
        let word = Self.currentWord(in: text)
        let language = locale.identifier
        let suggestions = await MainActor.run {
            Self.suggestions(for: word, language: language)
        }
        return .init(inputText: text, suggestions: suggestions)
    }

    /// The word being typed: the letters after the last space or punctuation.
    static func currentWord(in text: String) -> String {
        let word = text.reversed().prefix { $0.isLetter || $0 == "'" || $0 == "’" }
        return String(word.reversed())
    }

    @MainActor
    private static func suggestions(for word: String, language: String) -> [Autocomplete.Suggestion] {
        guard !word.isEmpty else { return [] }
        let checker = UITextChecker()
        let range = NSRange(location: 0, length: (word as NSString).length)
        let misspelled = checker.rangeOfMisspelledWord(
            in: word, range: range, startingAt: 0, wrap: false, language: language
        ).location != NSNotFound

        var suggestions: [Autocomplete.Suggestion] = []
        if misspelled {
            let guesses = checker.guesses(forWordRange: range, in: word, language: language) ?? []
            suggestions.append(.init(text: word, type: .unknown, title: "“\(word)”"))
            for (index, guess) in guesses.prefix(2).enumerated() {
                suggestions.append(.init(text: guess, type: index == 0 ? .autocorrect : .regular))
            }
        } else {
            let completions = checker.completions(forPartialWordRange: range, in: word, language: language) ?? []
            suggestions.append(.init(text: word))
            let extra = completions.filter { $0.caseInsensitiveCompare(word) != .orderedSame }
            suggestions.append(contentsOf: extra.prefix(2).map { .init(text: matchingCase(of: word, $0)) })
        }
        return suggestions
    }

    /// Keeps a capital the user typed: "Hel" completes to "Hello", not "hello".
    static func matchingCase(of typed: String, _ completion: String) -> String {
        guard let first = typed.first, first.isUppercase else { return completion }
        return completion.prefix(1).uppercased() + completion.dropFirst()
    }

    // Learning and ignoring words are not kept yet.

    var canIgnoreWords: Bool { false }
    var canLearnWords: Bool { false }
    var ignoredWords: [String] { [] }
    var learnedWords: [String] { [] }
    func hasIgnoredWord(_ word: String) -> Bool { false }
    func hasLearnedWord(_ word: String) -> Bool { false }
    func ignoreWord(_ word: String) {}
    func learnWord(_ word: String) {}
    func removeIgnoredWord(_ word: String) {}
    func unlearnWord(_ word: String) {}
}
