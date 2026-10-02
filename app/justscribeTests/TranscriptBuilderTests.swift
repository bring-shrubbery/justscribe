//
//  TranscriptBuilderTests.swift
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

import Testing
@testable import justscribe

struct TranscriptBuilderTests {

    private func words(_ items: [(String, Double, Double)]) -> [TimedWord] {
        items.map { TimedWord(text: $0.0, start: $0.1, end: $0.2) }
    }

    @Test func noWordsGiveNoParagraphs() {
        #expect(TranscriptBuilder.paragraphs(words: [], turns: []).isEmpty)
        #expect(TranscriptBuilder.text([]) == "")
    }

    @Test func withoutTurnsThereAreNoSpeakerLabels() {
        let result = TranscriptBuilder.paragraphs(
            words: words([(" Hello", 4.2, 4.6), (" there.", 4.7, 5.1)]), turns: [])
        #expect(result == [TranscriptParagraph(start: 4.2, speaker: nil, text: "Hello there.")])
    }

    @Test func aPauseOfOneAndAHalfSecondsStartsAParagraph() {
        let result = TranscriptBuilder.paragraphs(
            words: words([(" One", 0, 0.5), (" two", 0.5, 1.0), (" three", 2.5, 3.0), (" four", 4.25, 4.75)]),
            turns: [])
        // 1.0 → 2.5 is exactly 1.5 s: a break. 3.0 → 4.25 is 1.25 s: not a break.
        // (The times are exact in binary, so the comparison is not at the mercy of rounding.)
        #expect(result.map(\.text) == ["One two", "three four"])
        #expect(result.map(\.start) == [0, 2.5])
    }

    @Test func aSpeakerChangeStartsAParagraphAndSpeakersAreNumberedByFirstAppearance() {
        let turns = [
            SpeakerTurn(speaker: "S7", start: 0, end: 2),
            SpeakerTurn(speaker: "S2", start: 2, end: 4),
            SpeakerTurn(speaker: "S7", start: 4, end: 6),
        ]
        let result = TranscriptBuilder.paragraphs(
            words: words([(" Hi", 0.2, 0.5), (" Yes", 2.1, 2.4), (" Good", 4.1, 4.5)]), turns: turns)
        #expect(result.map(\.speaker) == [1, 2, 1])
    }

    @Test func aWordGoesToTheTurnItOverlapsMost() {
        let turns = [SpeakerTurn(speaker: "A", start: 0, end: 1.0), SpeakerTurn(speaker: "B", start: 1.0, end: 5)]
        // 0.8–1.4: 0.2 s with A, 0.4 s with B.
        let result = TranscriptBuilder.paragraphs(
            words: words([(" first", 0.1, 0.5), (" second", 0.8, 1.4)]), turns: turns)
        #expect(result.map(\.speaker) == [1, 2])
    }

    @Test func aWordInAGapGoesToTheNearestTurn() {
        let turns = [SpeakerTurn(speaker: "A", start: 0, end: 1), SpeakerTurn(speaker: "B", start: 5, end: 9)]
        // 4.2–4.6 touches neither; B (0.4 s away) is nearer than A (3.2 s away).
        let result = TranscriptBuilder.paragraphs(
            words: words([(" early", 0.2, 0.6), (" late", 4.2, 4.6)]), turns: turns)
        #expect(result.map(\.speaker) == [1, 2])
    }

    @Test func aSingleSpeakerDropsTheLabels() {
        let turns = [SpeakerTurn(speaker: "A", start: 0, end: 3), SpeakerTurn(speaker: "A", start: 3, end: 6)]
        let result = TranscriptBuilder.paragraphs(words: words([(" Just", 0.1, 0.4), (" me", 0.5, 0.8)]), turns: turns)
        #expect(result == [TranscriptParagraph(start: 0.1, speaker: nil, text: "Just me")])
    }

    @Test func aLongRunBreaksAtTheFirstSentenceEndAfterSixtySeconds() {
        // One word per second, no pauses; sentence ends at t=30 and t=64.
        var items: [(String, Double, Double)] = []
        for second in 0..<80 {
            let text = (second == 30 || second == 64) ? " end." : " word"
            items.append((text, Double(second), Double(second) + 0.9))
        }
        let result = TranscriptBuilder.paragraphs(words: words(items), turns: [])
        #expect(result.count == 2)
        #expect(result[1].start == 65)   // the break follows the sentence that ends at 64.9
    }

    @Test func aRunWithoutSentenceEndsBreaksAtNinetySeconds() {
        let items = (0..<100).map { (" word", Double($0), Double($0) + 0.9) }
        let result = TranscriptBuilder.paragraphs(words: words(items), turns: [])
        #expect(result.count == 2)
        #expect(result[1].start == 90)
    }

    @Test func piecesAreConcatenatedSoUnspacedLanguagesStayUnspaced() {
        let result = TranscriptBuilder.paragraphs(
            words: words([("こん", 0, 0.3), ("にちは", 0.3, 0.8), ("。", 0.8, 0.9)]), turns: [])
        #expect(result.map(\.text) == ["こんにちは。"])
    }

    @Test func textFormatsTimestampsSpeakersAndBlankLines() {
        let text = TranscriptBuilder.text([
            TranscriptParagraph(start: 4.9, speaker: 1, text: "So the first thing."),
            TranscriptParagraph(start: 3725.2, speaker: 2, text: "Right."),
        ])
        #expect(text == "[00:00:04] Speaker 1\nSo the first thing.\n\n[01:02:05] Speaker 2\nRight.")
    }

    @Test func textWithoutSpeakersHasOnlyTheTime() {
        let text = TranscriptBuilder.text([TranscriptParagraph(start: 61, speaker: nil, text: "Hello.")])
        #expect(text == "[00:01:01]\nHello.")
    }

    @Test func earlierParagraphsDoNotChangeAsWordsArrive() {
        let turns = [SpeakerTurn(speaker: "A", start: 0, end: 10), SpeakerTurn(speaker: "B", start: 10, end: 20)]
        let all = words([(" One", 1, 1.4), (" two.", 1.5, 2), (" Three", 11, 11.4), (" four", 11.5, 12)])
        let partial = TranscriptBuilder.paragraphs(words: Array(all.prefix(3)), turns: turns)
        let full = TranscriptBuilder.paragraphs(words: all, turns: turns)
        #expect(partial.count == 2 && full.count == 2)
        #expect(partial[0] == full[0])
        #expect(partial[1].speaker == 2)   // labelled from the turns, though only speaker 1 had spoken before
    }
}
