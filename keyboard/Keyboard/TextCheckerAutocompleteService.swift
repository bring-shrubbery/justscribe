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

/// Suggestions from the system spell checker, ranked by `SuggestionRanker`: the
/// word as typed, completions while a word is being typed, and a correction
/// applied on space when the word is one typo away from a real one.
///
/// Its state is written on the main thread only (`update(with:)`), so it is shared freely.
nonisolated final class TextCheckerAutocompleteService: AutocompleteService, @unchecked Sendable {

    var locale: Locale

    /// The user's text replacements, shortcut → phrase, from the supplementary lexicon.
    var replacements: [String: String] = [:]

    /// Words the spell checker does not know but the user does, such as contact names.
    var knownWords: Set<String> = []

    /// Common words, for completions and for ranking corrections.
    let words: WordList?

    init(locale: Locale) {
        self.locale = locale
        self.words = Bundle.main.url(forResource: "words-en", withExtension: "txt").flatMap(WordList.init(contentsOf:))
    }

    /// Asks the keyboard for the user's text replacements and contact names.
    ///
    /// UIKit calls back on a background thread; the entries are read there and
    /// applied on the main thread.
    func load(from controller: UIInputViewController) {
        controller.requestSupplementaryLexicon(completion: Self.lexiconHandler(for: self))
    }

    private static func lexiconHandler(
        for service: TextCheckerAutocompleteService
    ) -> @Sendable (UILexicon) -> Void {
        { lexicon in
            let entries = lexicon.entries.map { ($0.userInput, $0.documentText) }
            DispatchQueue.main.async { service.update(with: entries) }
        }
    }

    func update(with entries: [(userInput: String, documentText: String)]) {
        var replacements: [String: String] = [:]
        var known: Set<String> = []
        for entry in entries {
            if entry.userInput.caseInsensitiveCompare(entry.documentText) == .orderedSame {
                known.insert(entry.documentText.lowercased())
            } else {
                replacements[entry.userInput] = entry.documentText
            }
        }
        self.replacements = replacements
        self.knownWords = known
    }

    func autocomplete(_ text: String) async throws -> Autocomplete.ServiceResult {
        let word = SuggestionRanker.currentWord(in: text)
        let locale = locale
        let replacements = replacements
        let words = words
        // The list holds some typos ("helo" is about 23,000th), so only its common words count as correct.
        let isCommon = (words?.rank(of: word) ?? .max) < 15_000
        let isKnown = knownWords.contains(word.lowercased()) || isCommon
        let ranked = await MainActor.run {
            var input = Self.spellCheck(word, language: Self.checkerLanguage(for: locale))
            input.replacements = replacements
            if isKnown { input.isMisspelled = false }
            if let words {
                input.completions = words.completions(of: word, limit: 3) + input.completions
                input.rank = { words.rank(of: $0) }
            }
            return SuggestionRanker.suggestions(for: input)
        }
        let suggestions = ranked.map { suggestion -> Autocomplete.Suggestion in
            if suggestion.isAutocorrect { return .init(text: suggestion.text, type: .autocorrect) }
            if suggestion.isVerbatim { return .init(text: suggestion.text, type: .unknown, title: "“\(suggestion.text)”") }
            return .init(text: suggestion.text)
        }
        return .init(inputText: text, suggestions: suggestions)
    }

    /// The spell checker's name for the locale's language. A locale such as
    /// `en_US@rg=ltzzzz` (a region override) is not one, and gets no completions.
    @MainActor
    private static func checkerLanguage(for locale: Locale) -> String {
        let available = UITextChecker.availableLanguages
        let identifier = locale.identifier.split(separator: "@").first.map(String.init) ?? ""
        if available.contains(identifier) { return identifier }
        let code = locale.language.languageCode?.identifier ?? "en"
        return available.first { $0.hasPrefix(code) } ?? "en_US"
    }

    @MainActor
    private static func spellCheck(_ word: String, language: String) -> SuggestionRanker.Input {
        guard !word.isEmpty else { return .init(word: word, isMisspelled: false) }
        let checker = UITextChecker()
        let range = NSRange(location: 0, length: (word as NSString).length)
        let misspelled = checker.rangeOfMisspelledWord(
            in: word, range: range, startingAt: 0, wrap: false, language: language
        ).location != NSNotFound
        return .init(
            word: word,
            isMisspelled: misspelled,
            guesses: misspelled ? checker.guesses(forWordRange: range, in: word, language: language) ?? [] : [],
            completions: checker.completions(forPartialWordRange: range, in: word, language: language) ?? []
        )
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
