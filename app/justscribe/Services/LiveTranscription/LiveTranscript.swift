//
//  LiveTranscript.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 05/10/2026.
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

/// The pure parts of a live transcription: the labels its sources give words, how the
/// sources' words are woven into one transcript, and what counts as silence.
nonisolated enum LiveTranscript {
    /// The label of words from the microphone when system audio is recorded too.
    static let you = "you"
    /// The label of words from the system audio until the speaker pass tells them apart.
    static let others = "others"
    static let names = [you: "You", others: "Others"]

    /// Two words of one source closer than this belong to the same run.
    static let runGap = 1.0
    /// A sample this small, as the loudest in a chunk, is silence: about -60 dBFS.
    static let silencePeak: Float = 0.001

    /// The label a source's words carry: known only when there are two sources, so the
    /// transcript can tell the user from the rest.
    static func label(for kind: LiveAudioKind, among kinds: Set<LiveAudioKind>) -> String? {
        guard kinds.count >= 2 else { return nil }
        return kind == .microphone ? you : others
    }

    /// The sources' words as one list. Each source's words are grouped into runs (consecutive
    /// words less than `runGap` apart) and the runs are ordered by their start, so an
    /// interjection from one source lands between the other's runs instead of inside one of
    /// them word by word. Words within a run keep their order.
    static func merged(_ streams: [[TimedWord]]) -> [TimedWord] {
        var runs: [[TimedWord]] = []
        for words in streams {
            var run: [TimedWord] = []
            for word in words {
                if let last = run.last, word.start - last.end >= runGap {
                    runs.append(run)
                    run = []
                }
                run.append(word)
            }
            if !run.isEmpty { runs.append(run) }
        }
        // Stable: runs that start together keep the order of their sources.
        return runs.enumerated()
            .sorted { ($0.element[0].start, $0.offset) < ($1.element[0].start, $1.offset) }
            .flatMap(\.element)
    }

    /// Whether nothing worth the speech model's time is in `samples`: system audio with
    /// nothing playing is exact zeros, and a muted microphone close to it.
    static func isSilent(_ samples: [Float]) -> Bool {
        !samples.contains { abs($0) >= silencePeak }
    }
}
