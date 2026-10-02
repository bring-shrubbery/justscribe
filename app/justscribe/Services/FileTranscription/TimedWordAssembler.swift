//
//  TimedWordAssembler.swift
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

import Foundation

/// Joins a speech model's sub-word tokens into words. Parakeet reports a time for every
/// token; a token that begins with a space (or the SentencePiece marker) starts a new word,
/// and any other token continues the word before it.
nonisolated enum TimedWordAssembler {
    static func words(fromTokens tokens: [TimedWord]) -> [TimedWord] {
        var words: [TimedWord] = []
        for token in tokens {
            let text = token.text.replacingOccurrences(of: "▁", with: " ")
            if text.isEmpty { continue }
            if text.hasPrefix(" ") || words.isEmpty {
                words.append(TimedWord(text: text.hasPrefix(" ") ? text : " " + text, start: token.start, end: token.end))
            } else {
                words[words.count - 1].text += text
                words[words.count - 1].end = token.end
            }
        }
        return words
    }

    /// Pads `samples` with trailing silence up to `minimum` samples. Parakeet rejects audio
    /// under 0.3 s, and a file's last chunk can be that short; silence at the end does not
    /// move the times of the words before it.
    static func paddedToMinimum(_ samples: [Float], minimum: Int = 16_000) -> [Float] {
        guard samples.count < minimum else { return samples }
        return samples + [Float](repeating: 0, count: minimum - samples.count)
    }
}
