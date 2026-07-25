//
//  GrammarTextChunkerTests.swift
//  justscribe
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

struct GrammarTextChunkerTests {

    @Test func emptyTextYieldsNoChunks() {
        #expect(GrammarTextChunker.chunks("").isEmpty)
    }

    @Test func shortTextIsASingleChunk() {
        let text = "Hello there. How are you?"
        #expect(GrammarTextChunker.chunks(text, maxLength: 2000) == [text])
    }

    /// The load-bearing invariant: chunking never adds, drops, or reorders characters.
    @Test(arguments: [
        "",
        "   \n\n  ",
        "One sentence.",
        "Line one.\nLine two.\n\nLine three.",
        String(repeating: "This is a sentence. ", count: 40),
        String(repeating: "word ", count: 200),
        String(repeating: "x", count: 500),
        "Dr. Smith went to Washington. He arrived at 3 p.m. It was raining!  Then he left.",
    ])
    func joiningChunksReproducesTheInput(text: String) {
        #expect(GrammarTextChunker.chunks(text, maxLength: 100).joined() == text)
    }

    @Test func chunksRespectMaxLength() {
        let text = String(repeating: "This is a sentence. ", count: 40)
        for chunk in GrammarTextChunker.chunks(text, maxLength: 100) {
            #expect(chunk.count <= 100)
        }
    }

    @Test func oversizedSentenceIsSplitOnWordBoundaries() {
        let sentence = String(repeating: "alpha beta gamma ", count: 20) + "."
        let chunks = GrammarTextChunker.chunks(sentence, maxLength: 100)
        #expect(chunks.count > 1)
        #expect(chunks.joined() == sentence)
        for chunk in chunks {
            #expect(chunk.count <= 100)
        }
    }

    @Test func singleWordLongerThanMaxIsEmittedWhole() {
        let word = String(repeating: "x", count: 250)
        #expect(GrammarTextChunker.chunks(word, maxLength: 100) == [word])
    }
}
