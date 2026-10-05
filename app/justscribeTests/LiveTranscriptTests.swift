//
//  LiveTranscriptTests.swift
//  justscribeTests
//
//  Created by Antoni Silvestrovic on 24/01/2026.
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

struct LiveTranscriptTests {
    private func words(_ items: [(String, Double, Double)], speaker: String? = nil) -> [TimedWord] {
        items.map { TimedWord(text: $0.0, start: $0.1, end: $0.2, speaker: speaker) }
    }

    @Test func labelsExistOnlyWithTwoSources() {
        #expect(LiveTranscript.label(for: .microphone, among: [.microphone]) == nil)
        #expect(LiveTranscript.label(for: .systemAudio, among: [.systemAudio]) == nil)
        #expect(LiveTranscript.label(for: .microphone, among: [.microphone, .systemAudio]) == LiveTranscript.you)
        #expect(LiveTranscript.label(for: .systemAudio, among: [.microphone, .systemAudio]) == LiveTranscript.others)
        #expect(LiveTranscript.names[LiveTranscript.you] == "You")
    }

    @Test func anInterjectionLandsBetweenRunsNotInsideOne() {
        let mine = words([(" I", 0, 0.3), (" think", 0.3, 0.6), (" so.", 0.6, 1.0), (" Right.", 4, 4.5)], speaker: "you")
        let theirs = words([(" Yeah", 0.5, 0.8), (" sure", 0.8, 1.1)], speaker: "others")
        let merged = LiveTranscript.merged([mine, theirs])
        #expect(merged.map(\.text) == [" I", " think", " so.", " Yeah", " sure", " Right."])
    }

    @Test func runsThatStartTogetherKeepTheirSourcesOrder() {
        let mine = words([(" A", 0, 1)])
        let theirs = words([(" B", 0, 1)])
        #expect(LiveTranscript.merged([mine, theirs]).map(\.text) == [" A", " B"])
        #expect(LiveTranscript.merged([theirs, mine]).map(\.text) == [" B", " A"])
    }

    @Test func aGapOfOneSecondSplitsARun() {
        let mine = words([(" One", 0, 1), (" Two", 2, 3)])
        let theirs = words([(" Between", 1.2, 1.8)])
        #expect(LiveTranscript.merged([mine, theirs]).map(\.text) == [" One", " Between", " Two"])
        // 0.99 s is not a gap: "Between" waits for the run to end.
        let close = words([(" One", 0, 1), (" Two", 1.99, 3)])
        #expect(LiveTranscript.merged([close, theirs]).map(\.text) == [" One", " Two", " Between"])
    }

    @Test func silenceIsExactZerosOrNearlySo() {
        #expect(LiveTranscript.isSilent([]))
        #expect(LiveTranscript.isSilent([Float](repeating: 0, count: 16_000)))
        #expect(LiveTranscript.isSilent([0.0005, -0.0009]))
        #expect(!LiveTranscript.isSilent([0, 0, 0.002, 0]))
    }
}
