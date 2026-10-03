//
//  VocabularyMatcherTests.swift
//  justscribeTests
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
import Testing
@testable import justscribe

@Suite(.timeLimit(.minutes(1)))
struct VocabularyMatcherTests {

    private let dictionary: Set<String> = ["the", "a", "mark", "marc", "quantum", "swift", "ui", "send", "i", "met", "at", "noon", "and", "talked", "to", "yesterday", "hello", "world", "team", "open", "now", "file", "like", "by", "really", "lot"]
    private func isWord(_ w: String) -> Bool { dictionary.contains(w.lowercased()) }
    private func entry(_ text: String, _ heardAs: [String] = []) -> VocabularyEntry {
        VocabularyEntry(id: UUID(), text: text, heardAs: heardAs, createdAt: Date())
    }
    private func fix(_ text: String, _ entries: [VocabularyEntry]) -> String {
        VocabularyMatcher.apply(text, entries: entries, isDictionaryWord: isWord)
    }

    @Test func aHeardAsFormIsReplacedWhateverTheSpacingHyphensAndCase() {
        let e = [entry("SwiftUI", ["swift ui"])]
        #expect(fix("I like swift UI a lot", e) == "I like SwiftUI a lot")
        #expect(fix("I like Swift-ui, really", e) == "I like SwiftUI, really")
        #expect(fix("swift ui.", e) == "SwiftUI.")
    }

    @Test func aNonDictionaryWordThatSoundsLikeAnEntryIsReplaced() {
        let e = [entry("Quassum"), entry("Antoni")]
        #expect(fix("I met quasum at noon", e) == "I met Quassum at noon")
        #expect(fix("Antony and I talked", e) == "Antoni and I talked")
        #expect(fix("Hello, antoni!", e) == "Hello, Antoni!")
    }

    @Test func dictionaryWordsAreNeverReplacedBySound() {
        let e = [entry("Marc"), entry("Quassum")]
        #expect(fix("I met mark at noon", e) == "I met mark at noon")
        #expect(fix("quantum", e) == "quantum")
        // ...unless the user says so with a form.
        #expect(fix("I met mark at noon", [entry("Marc", ["mark"])]) == "I met Marc at noon")
    }

    @Test func distanceBoundsFollowTheKeyLength() {
        #expect(VocabularyMatcher.editDistance("antoni", "antony") == 1)
        #expect(VocabularyMatcher.editDistance("quasum", "quassum") == 1)
        #expect(VocabularyMatcher.editDistance("kitten", "sitting") == 3)
        #expect(fix("tteam", [entry("Team")]) == "Team")       // not a dictionary word; distance 1 is within the bound for a 4-letter key
        #expect(fix("teamed", [entry("Team")]) == "teamed")    // distance 2 is past the bound for a 4-letter key
    }

    @Test func phoneticKeysAgreeForKnownPairs() {
        #expect(VocabularyMatcher.phoneticKey("Antoni") == VocabularyMatcher.phoneticKey("Antony"))
        #expect(VocabularyMatcher.phoneticKey("Quassum") == VocabularyMatcher.phoneticKey("quasum"))
        #expect(VocabularyMatcher.phoneticKey("Smith") == VocabularyMatcher.phoneticKey("Smyth"))
        #expect(VocabularyMatcher.phoneticKey("John") == VocabularyMatcher.phoneticKey("Jon"))
        #expect(VocabularyMatcher.phoneticKey("Kristin") == VocabularyMatcher.phoneticKey("Christine"))
        #expect(VocabularyMatcher.phoneticKey("Antoni") != VocabularyMatcher.phoneticKey("Quassum"))
    }

    @Test func multiWordEntriesMatchRuns() {
        let e = [entry("Neural Sheet", ["neural sheets"])]
        #expect(fix("open neural sheets now", e) == "open Neural Sheet now")
        #expect(fix("the nural sheet file", e) == "the Neural Sheet file")
    }

    @Test func applyingTwiceChangesNothing() {
        let e = [entry("SwiftUI", ["swift ui"]), entry("Quassum"), entry("Antoni")]
        let once = fix("swift ui by quasum and antony", e)
        #expect(once == "SwiftUI by Quassum and Antoni")
        #expect(fix(once, e) == once)
    }

    @Test func theWordFormKeepsCountAndAffixes() {
        let words = [" I", " like", " swift", " UI,", " really"]
        let out = VocabularyMatcher.apply(words: words, entries: [entry("SwiftUI", ["swift ui"])], isDictionaryWord: isWord)
        #expect(out == [" I", " like", " SwiftUI,", "", " really"])
    }

    @Test func emptyInputsAreSafe() {
        #expect(fix("", [entry("X")]) == "")
        #expect(fix("hello world", []) == "hello world")
        #expect(VocabularyMatcher.apply(words: [], entries: [entry("X")], isDictionaryWord: isWord).isEmpty)
    }

    @Test func aPossessiveSurvivesTheReplacement() {
        #expect(fix("Antoni's book", [entry("Antoni")]) == "Antoni's book")
        #expect(fix("antony's book", [entry("Antoni")]) == "Antoni's book")
        #expect(fix("antony\u{2019}s book", [entry("Antoni")]) == "Antoni\u{2019}s book")
    }

    @Test func digitsInAnEntryMustBeHeard() {
        #expect(fix("GPT 4 is out", [entry("GPT-4")]) == "GPT 4 is out")
        #expect(fix("gpt four is out", [entry("GPT-4")]) == "gpt four is out")
        #expect(fix("gpt4 is out", [entry("GPT-4")]) == "GPT-4 is out")
    }

    @Test func aRunNeverCrossesClausePunctuation() {
        #expect(fix("written in Swift. UI design", [entry("SwiftUI", ["swift ui"])]) == "written in Swift. UI design")
        #expect(fix("Swift, UI", [entry("SwiftUI", ["swift ui"])]) == "Swift, UI")
    }

    @Test func anExactSpellingIsSettledBeforeSoundAlikes() {
        #expect(fix("Antoni", [entry("Antony"), entry("Antoni")]) == "Antoni")
        let e = [entry("Antony"), entry("Antoni", ["anthony"])]
        let once = fix("anthony", e)
        #expect(once == "Antoni")
        #expect(fix(once, e) == "Antoni")
    }

    @Test func dictionaryWordsAreNotRecasedByAnExactMatch() {
        let words: Set<String> = ["linear", "regression", "and", "go"]
        let out = VocabularyMatcher.apply("linear regression and go", entries: [entry("Linear"), entry("Go")]) { words.contains($0.lowercased()) }
        #expect(out == "linear regression and go")
    }

    @Test func veryShortEntriesMatchOnlyByFormOrSpelling() {
        #expect(fix("ay uh eh", [entry("AI")]) == "ay uh eh")
        #expect(fix("Al a1", [entry("AI")]) == "Al a1")
        #expect(fix("ay", [entry("AI", ["ay"])]) == "AI")
        #expect(fix("ai", [entry("AI")]) == "AI")
    }

    @Test func eachWordIsLookedUpInTheDictionaryAtMostOnce() {
        final class Counter { var calls = 0 }
        let a = ["ka", "lo", "mi", "ra", "tu", "ne", "si", "po"]
        let b = ["zor", "bex", "quil", "dap", "fen", "gru"]
        let words: [String] = (0..<300).map { (i: Int) -> String in
            let syllables: [String] = [a[i % 8], a[(i / 8) % 8], a[(i / 64) % 8]]
            return " " + syllables.joined()
        }
        let entries: [VocabularyEntry] = (0..<200).map { (i: Int) -> VocabularyEntry in
            let syllables: [String] = [b[i % 6], b[(i / 6) % 6], b[(i / 36) % 6]]
            return entry(syllables.joined())
        }
        let counter = Counter()
        let out = VocabularyMatcher.apply(words: words, entries: entries) { _ in counter.calls += 1; return false }
        #expect(out.count == 300)
        #expect(counter.calls <= 300)
        #expect(VocabularyMatcher.editDistance("ab", "abcdef", limit: 2) == 3)
    }

    @Test func anEntryEndingInApostropheSKeepsItsSpelling() {
        let e = [entry("McDonald's")]
        #expect(fix("we ate at McDonald's", e) == "we ate at McDonald's")
        #expect(fix("we ate at mcdonald\u{2019}s.", e) == "we ate at McDonald's.")
        let once = fix("mcdonalds", e)
        #expect(once == "McDonald's")
        #expect(fix(once, e) == once)
        #expect(fix("mcdonald's", [entry("McDonald's", ["mcdonalds"])]) == "McDonald's")
        #expect(fix("macys and lowes", [entry("Macy's"), entry("Lowe's")]) == "Macy's and Lowe's")
        #expect(fix("Antoni's and antony's", [entry("Antoni")]) == "Antoni's and Antoni's")
    }
}
