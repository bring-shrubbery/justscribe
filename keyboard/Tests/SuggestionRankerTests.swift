//
//  SuggestionRankerTests.swift
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

import Testing
@testable import JustScribe

struct SuggestionRankerTests {

    private typealias Suggestion = SuggestionRanker.Suggestion

    @Test func oneTypoAwayIsCorrectedOnSpace() {
        let input = SuggestionRanker.Input(word: "Helo", isMisspelled: true, guesses: ["Hello", "Help", "Halo"])
        #expect(SuggestionRanker.suggestions(for: input) == [
            Suggestion(text: "Helo", isVerbatim: true),
            Suggestion(text: "Hello", isAutocorrect: true),
            Suggestion(text: "Help"),
        ])
    }

    @Test func aWordStillBeingTypedGetsCompletionsAndNoCorrection() {
        let input = SuggestionRanker.Input(
            word: "wor", isMisspelled: true, guesses: ["woe", "wot"], completions: ["work", "world", "word"]
        )
        #expect(SuggestionRanker.suggestions(for: input) == [
            Suggestion(text: "wor"), Suggestion(text: "work"), Suggestion(text: "world"),
        ])
    }

    @Test func aFarOffGuessIsSuggestedButNotApplied() {
        let input = SuggestionRanker.Input(word: "xqzt", isMisspelled: true, guesses: ["quartz"])
        let suggestions = SuggestionRanker.suggestions(for: input)
        #expect(!suggestions.contains { $0.isAutocorrect })
        #expect(suggestions.map(\.text) == ["xqzt", "quartz"])
    }

    @Test func aCorrectWordOffersCompletions() {
        let input = SuggestionRanker.Input(word: "Hel", isMisspelled: false, completions: ["hello", "help", "hel"])
        #expect(SuggestionRanker.suggestions(for: input).map(\.text) == ["Hel", "Hello", "Help"])
    }

    @Test func contractionsAndLoneIAreFixed() {
        #expect(SuggestionRanker.suggestions(for: .init(word: "dont", isMisspelled: false))
            .first { $0.isAutocorrect }?.text == "don't")
        #expect(SuggestionRanker.suggestions(for: .init(word: "Im", isMisspelled: true))
            .first { $0.isAutocorrect }?.text == "I'm")
        #expect(SuggestionRanker.suggestions(for: .init(word: "i", isMisspelled: false))
            .first { $0.isAutocorrect }?.text == "I")
    }

    @Test func textReplacementsWin() {
        let input = SuggestionRanker.Input(word: "omw", isMisspelled: true, guesses: ["mow"], replacements: ["omw": "On my way!"])
        #expect(SuggestionRanker.suggestions(for: input).first { $0.isAutocorrect }?.text == "On my way!")
    }

    @Test func currentWordIsTheLastRunOfLetters() {
        #expect(SuggestionRanker.currentWord(in: "Hello wor") == "wor")
        #expect(SuggestionRanker.currentWord(in: "I don't") == "don't")
        #expect(SuggestionRanker.currentWord(in: "Hello, ") == "")
    }

    @Test func editDistance() {
        #expect(SuggestionRanker.editDistance("helo", "hello") == 1)
        #expect(SuggestionRanker.editDistance("teh", "the") == 1)
        #expect(SuggestionRanker.editDistance("", "abc") == 3)
    }

    @Test func aMissedLetterBeatsAMoreCommonWrongOne() {
        let ranks = ["help": 133, "hello": 195, "hell": 600]
        let input = SuggestionRanker.Input(
            word: "Helo", isMisspelled: true, guesses: ["Help", "Hell", "Hello"], rank: { ranks[$0.lowercased()] }
        )
        #expect(SuggestionRanker.suggestions(for: input).first { $0.isAutocorrect }?.text == "Hello")
    }

    @Test func amongEqualTyposTheCommonerWordWins() {
        let ranks = ["work": 300, "word": 400]
        #expect(SuggestionRanker.bestCorrection(of: "wprk", among: ["word", "work"], rank: { ranks[$0] }) == "work")
    }
}

struct WordListTests {

    private let list = WordList(wordsByFrequency: ["the", "world", "work", "word", "wore", "wor"])

    @Test func completionsComeMostCommonFirst() {
        #expect(list.completions(of: "wor") == ["world", "work", "word"])
        #expect(list.completions(of: "WOR", limit: 1) == ["world"])
    }

    @Test func completionsLeaveOutTheWordItself() {
        #expect(!list.completions(of: "wor", limit: 10).contains("wor"))
        #expect(list.completions(of: "xyz").isEmpty)
    }

    @Test func rankIsThePositionInTheList() {
        #expect(list.rank(of: "the") == 0)
        #expect(list.rank(of: "Work") == 2)
        #expect(list.rank(of: "nope") == nil)
    }
}
