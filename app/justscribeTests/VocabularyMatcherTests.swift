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
}
