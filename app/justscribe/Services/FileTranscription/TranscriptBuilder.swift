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
/// except that the last one may grow.
///
/// Speaker labels are shown whenever the turns hold two or more speakers, even if every word
/// so far went to one of them: the turns are complete before transcription starts, so the
/// decision cannot flip while words stream in. Numbers are given in order of the first word
/// each speaker is assigned, so a turn that wins no words leaves no gap, and numbers already
/// given never change as words are appended.
nonisolated enum TranscriptBuilder {
    /// A silence this long between two words starts a new paragraph.
    static let pauseBreak = 1.5
    /// Once a paragraph is this long it ends at the next sentence end.
    static let softLimit = 60.0
    /// A paragraph never runs longer than this.
    static let hardLimit = 90.0

    private static let sentenceEnds: Set<Character> = [".", "?", "!", "。", "？", "！"]
    /// Closing quotes and brackets that may follow a sentence end.
    private static let closers: Set<Character> = ["\"", "'", "”", "’", ")", "]", "」", "』"]

    static func paragraphs(words: [TimedWord], turns: [SpeakerTurn]) -> [TranscriptParagraph] {
        let labelled = Set(turns.map(\.speaker)).count >= 2
        var numbers: [String: Int] = [:]
        var result: [TranscriptParagraph] = []
        var previous: TimedWord?

        for word in words where !word.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Punctuation belongs to the words before it, whichever turn its time falls in.
            if !result.isEmpty, isPunctuationOnly(word.text) {
                result[result.count - 1].text += word.text
            } else {
                var speaker: Int?
                if labelled, let label = diarizerLabel(for: word, in: turns) {
                    speaker = numbers[label] ?? (numbers.count + 1)
                    numbers[label] = speaker
                }
                var startsParagraph = result.isEmpty
                if let previous, let current = result.last {
                    let length = previous.end - current.start
                    startsParagraph = speaker != current.speaker
                        || word.start - previous.end >= pauseBreak
                        || word.end - current.start > hardLimit
                        || (length >= softLimit && endsSentence(previous.text))
                }
                if startsParagraph {
                    result.append(TranscriptParagraph(start: word.start, speaker: speaker, text: word.text))
                } else {
                    result[result.count - 1].text += word.text
                }
            }
            previous = word
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

    /// `3725.9` → `01:02:05` (rounded down). Non-finite input gives `00:00:00`.
    static func timestamp(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "00:00:00" }
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// Whether the piece ends a sentence, looking past closing quotes and brackets.
    private static func endsSentence(_ text: String) -> Bool {
        let last = text.reversed().first { !$0.isWhitespace && !closers.contains($0) }
        return last.map { sentenceEnds.contains($0) } ?? false
    }

    private static func isPunctuationOnly(_ text: String) -> Bool {
        text.allSatisfy { $0.isPunctuation || $0.isWhitespace }
    }

    /// The label of the turn the word overlaps most; when it overlaps none, the turn nearest in time.
    private static func diarizerLabel(for word: TimedWord, in turns: [SpeakerTurn]) -> String? {
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
