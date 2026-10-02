//
//  TimedText.swift
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

/// A word, or a word-sized piece, with its place in the file in seconds.
/// `text` is as the model produced it: it begins with a space when the piece starts a new
/// word in a language that separates words with spaces, and has none otherwise, so pieces
/// are joined by concatenation.
nonisolated struct TimedWord: Equatable, Sendable {
    var text: String
    var start: Double
    var end: Double
}

/// Who spoke between two times, from the diarizer. `speaker` is the diarizer's own label.
nonisolated struct SpeakerTurn: Equatable, Sendable {
    var speaker: String
    var start: Double
    var end: Double
}

/// One paragraph of the transcript. `speaker` is 1-based, nil when speakers are not shown.
nonisolated struct TranscriptParagraph: Equatable, Sendable {
    var start: Double
    var speaker: Int?
    var text: String
}
