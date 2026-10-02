//
//  TranscriptBuilder.swift
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

/// Turns timed words and speaker turns into the paragraphs of a transcript. Pure: no models,
/// no clock. Safe to call again with more words: paragraphs already produced do not change,
/// except that the last one may grow, because speaker numbers come from the turns (which
/// are complete before transcription starts), not from the words seen so far.
nonisolated enum TranscriptBuilder {
    /// A silence this long between two words starts a new paragraph.
    static let pauseBreak = 1.5
    /// Once a paragraph is this long it ends at the next sentence end.
    static let softLimit = 60.0
    /// A paragraph never runs longer than this.
    static let hardLimit = 90.0

    static func paragraphs(words: [TimedWord], turns: [SpeakerTurn]) -> [TranscriptParagraph] {
        let numbers = speakerNumbers(turns)
        let labelled = numbers.count >= 2
        var result: [TranscriptParagraph] = []
        var previous: TimedWord?
        var previousSpeaker: Int?

        for word in words where !word.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let speaker = labelled ? speaker(for: word, in: turns).flatMap { numbers[$0] } : nil
            var startsParagraph = result.isEmpty
            if let previous, let current = result.last {
                let length = previous.end - current.start
                let endsSentence = previous.text.trimmingCharacters(in: .whitespaces).last.map { ".?!".contains($0) } ?? false
                startsParagraph = speaker != previousSpeaker
                    || word.start - previous.end >= pauseBreak
                    || word.end - current.start > hardLimit
                    || (length >= softLimit && endsSentence)
            }
            if startsParagraph {
                result.append(TranscriptParagraph(start: word.start, speaker: speaker, text: word.text))
            } else {
                result[result.count - 1].text += word.text
            }
            previous = word
            previousSpeaker = speaker
        }
        return result.map { paragraph in
            var tidy = paragraph
            tidy.text = paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return tidy
        }
    }

    static func text(_ paragraphs: [TranscriptParagraph]) -> String {
        paragraphs.map { paragraph in
            let label = paragraph.speaker.map { " Speaker \($0)" } ?? ""
            return "[\(timestamp(paragraph.start))]\(label)\n\(paragraph.text)"
        }.joined(separator: "\n\n")
    }

    /// `3725.9` → `01:02:05` (rounded down).
    static func timestamp(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// The diarizer's labels numbered 1, 2, … in order of first appearance.
    private static func speakerNumbers(_ turns: [SpeakerTurn]) -> [String: Int] {
        var numbers: [String: Int] = [:]
        for turn in turns.sorted(by: { $0.start < $1.start }) where numbers[turn.speaker] == nil {
            numbers[turn.speaker] = numbers.count + 1
        }
        return numbers
    }

    /// The turn the word overlaps most; when it overlaps none, the turn nearest in time.
    private static func speaker(for word: TimedWord, in turns: [SpeakerTurn]) -> String? {
        var best: (speaker: String, overlap: Double, distance: Double)?
        for turn in turns {
            let overlap = max(0, min(word.end, turn.end) - max(word.start, turn.start))
            let distance = overlap > 0 ? 0 : max(turn.start - word.end, word.start - turn.end)
            if let current = best {
                let better = overlap > current.overlap || (overlap == current.overlap && distance < current.distance)
                if better { best = (turn.speaker, overlap, distance) }
            } else {
                best = (turn.speaker, overlap, distance)
            }
        }
        return best?.speaker
    }
}
