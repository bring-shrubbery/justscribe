//
//  TimedWordAssemblerTests.swift
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

struct TimedWordAssemblerTests {
    private func token(_ text: String, _ start: Double, _ end: Double) -> TimedWord {
        TimedWord(text: text, start: start, end: end)
    }

    @Test func noTokensGiveNoWords() {
        #expect(TimedWordAssembler.words(fromTokens: []).isEmpty)
    }

    @Test func tokensWithoutALeadingSpaceContinueTheWord() {
        let words = TimedWordAssembler.words(fromTokens: [
            token(" trans", 0.0, 0.2), token("crip", 0.2, 0.4), token("tion", 0.4, 0.7), token(" works", 0.8, 1.2),
        ])
        #expect(words == [token(" transcription", 0.0, 0.7), token(" works", 0.8, 1.2)])
    }

    @Test func theSentencePieceMarkerCountsAsALeadingSpace() {
        let words = TimedWordAssembler.words(fromTokens: [token("▁Hello", 0, 0.3), token("▁there", 0.4, 0.7)])
        #expect(words.map(\.text) == [" Hello", " there"])
    }

    @Test func theFirstTokenStartsAWordEvenWithoutASpace() {
        let words = TimedWordAssembler.words(fromTokens: [token("Hel", 0, 0.2), token("lo", 0.2, 0.4)])
        #expect(words == [token(" Hello", 0, 0.4)])
    }

    @Test func punctuationAttachesToTheWordBeforeIt() {
        let words = TimedWordAssembler.words(fromTokens: [token(" Yes", 0, 0.3), token(".", 0.3, 0.35), token(" No", 0.6, 0.8)])
        #expect(words.map(\.text) == [" Yes.", " No"])
    }

    @Test func emptyTokensAreSkipped() {
        let words = TimedWordAssembler.words(fromTokens: [token(" a", 0, 0.1), token("", 0.1, 0.2), token(" b", 0.3, 0.4)])
        #expect(words.map(\.text) == [" a", " b"])
    }

    @Test func aChunkStartingWithPunctuationGetsNoLeadingSpace() {
        let words = TimedWordAssembler.words(fromTokens: [token(",", 0, 0.1), token(" and", 0.2, 0.4)])
        #expect(words == [token(",", 0, 0.1), token(" and", 0.2, 0.4)])
        #expect(TimedWordAssembler.words(fromTokens: [token("...", 0, 0.1)]).map(\.text) == ["..."])
    }

    // MARK: - Padding short audio

    @Test func theMinimumsAreOneSecondForParakeetAndTwoForWhisper() {
        #expect(TimedWordAssembler.parakeetMinimumSamples == 16_000)
        #expect(TimedWordAssembler.whisperMinimumSamples == 32_000)
    }

    @Test func aOneSecondBufferIsPaddedToTwoSecondsForWhisper() {
        let oneSecond = [Float](repeating: 0.1, count: 16_000)
        let padded = TimedWordAssembler.paddedToMinimum(oneSecond, minimum: TimedWordAssembler.whisperMinimumSamples)
        #expect(padded.count == 32_000)
        #expect(Array(padded.prefix(16_000)) == oneSecond)
        #expect(padded.dropFirst(16_000).allSatisfy { $0 == 0 })
    }

    @Test func aBufferOverTwoSecondsIsUnchangedForWhisper() {
        let longer = [Float](repeating: 0.2, count: 40_000)
        #expect(TimedWordAssembler.paddedToMinimum(longer, minimum: TimedWordAssembler.whisperMinimumSamples) == longer)
    }

    @Test func aShortBufferIsPaddedWithZerosToOneSecond() {
        let padded = TimedWordAssembler.paddedToMinimum([0.5, -0.25, 0.75])
        #expect(padded.count == 16_000)
        #expect(Array(padded.prefix(3)) == [0.5, -0.25, 0.75])
        #expect(padded.dropFirst(3).allSatisfy { $0 == 0 })
    }

    @Test func aBufferOfOneSecondOrMoreIsUnchanged() {
        let exact = [Float](repeating: 0.1, count: 16_000)
        let longer = [Float](repeating: 0.2, count: 20_000)
        #expect(TimedWordAssembler.paddedToMinimum(exact) == exact)
        #expect(TimedWordAssembler.paddedToMinimum(longer) == longer)
    }

    @Test func anEmptyBufferBecomesOneSecondOfSilence() {
        #expect(TimedWordAssembler.paddedToMinimum([]) == [Float](repeating: 0, count: 16_000))
    }
}
