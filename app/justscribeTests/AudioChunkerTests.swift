//
//  AudioChunkerTests.swift
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

struct AudioChunkerTests {
    private let rate = AudioChunker.sampleRate

    /// `seconds` of a constant-amplitude tone, so every 100 ms window is equally loud.
    private func tone(seconds: Double, amplitude: Float = 0.5) -> [Float] {
        (0..<Int(seconds * Double(rate))).map { $0 % 2 == 0 ? amplitude : -amplitude }
    }

    private func allChunks(_ input: [Float], feed: Int = 4_096) -> [AudioChunk] {
        var chunker = AudioChunker()
        var chunks: [AudioChunk] = []
        var index = 0
        while index < input.count {
            let next = min(index + feed, input.count)
            chunks += chunker.append(Array(input[index..<next]))
            index = next
        }
        if let last = chunker.finish() { chunks.append(last) }
        return chunks
    }

    @Test func emptyInputYieldsNoChunks() {
        #expect(allChunks([]).isEmpty)
    }

    @Test func aClipShorterThanTwentySecondsIsOneChunk() {
        let input = tone(seconds: 7.5)
        let chunks = allChunks(input)
        #expect(chunks.count == 1)
        #expect(chunks[0].samples == input)
        #expect(chunks[0].startSeconds == 0)
    }

    @Test func chunksConcatenateToTheInput() {
        let input = tone(seconds: 95.3)
        #expect(allChunks(input).flatMap(\.samples) == input)
    }

    @Test func everyChunkButTheLastIsTwentyToThirtySeconds() {
        let chunks = allChunks(tone(seconds: 200))
        #expect(chunks.count >= 2)
        for chunk in chunks.dropLast() {
            #expect(chunk.samples.count >= 20 * rate)
            #expect(chunk.samples.count <= 30 * rate)
        }
        #expect(chunks.last.map { !$0.samples.isEmpty } == true)
    }

    @Test func startOffsetsFollowTheSamplesBefore() {
        let chunks = allChunks(tone(seconds: 70))
        var samplesBefore = 0
        for chunk in chunks {
            #expect(chunk.startSeconds == Double(samplesBefore) / Double(rate))
            samplesBefore += chunk.samples.count
        }
    }

    @Test func theCutLandsInAPlantedSilence() {
        // 40 s of tone with 300 ms of silence starting at 24.0 s.
        var input = tone(seconds: 40)
        let silenceStart = 24 * rate
        for index in silenceStart..<(silenceStart + 3 * rate / 10) { input[index] = 0 }
        let first = allChunks(input)[0]
        #expect(first.samples.count >= silenceStart)
        #expect(first.samples.count <= silenceStart + 3 * rate / 10)
    }

    @Test func theResultDoesNotDependOnHowTheInputArrives() {
        let input = tone(seconds: 65)
        #expect(allChunks(input, feed: 1_000).map(\.samples.count) == allChunks(input, feed: 100_000).map(\.samples.count))
    }

    @Test func theLengthsCanBeChosen() {
        var chunker = AudioChunker(minimumSeconds: 10, maximumSeconds: 15)
        var chunks = chunker.append(tone(seconds: 40))
        if let last = chunker.finish() { chunks.append(last) }
        #expect(chunks.count == 3)
        for chunk in chunks.dropLast() {
            #expect(chunk.samples.count >= 10 * rate && chunk.samples.count <= 15 * rate)
        }
        #expect(chunks.flatMap(\.samples).count == 40 * rate)
        #expect(chunks[1].startSeconds == Double(chunks[0].samples.count) / Double(rate))
    }
}
