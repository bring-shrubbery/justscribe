//
//  AudioChunker.swift
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

/// A stretch of 16 kHz mono audio and where it starts in the file.
nonisolated struct AudioChunk: Equatable, Sendable {
    var samples: [Float]
    var startSeconds: Double
}

/// Cuts a stream of samples into chunks of 20 to 30 seconds for the speech model. Each cut
/// is placed in the quietest 100 ms of the last ten seconds, so a word is rarely split.
/// The chunks concatenated are exactly the input.
nonisolated struct AudioChunker {
    static let sampleRate = 16_000
    private static let minimum = 20 * sampleRate
    private static let maximum = 30 * sampleRate
    private static let window = sampleRate / 10

    private var pending: [Float] = []
    private var emitted = 0

    /// Adds samples and returns every chunk that is now complete.
    mutating func append(_ samples: [Float]) -> [AudioChunk] {
        pending += samples
        var chunks: [AudioChunk] = []
        while pending.count >= Self.maximum {
            chunks.append(take(Self.cutIndex(in: pending)))
        }
        return chunks
    }

    /// The remainder, once the input has ended; nil when nothing is left.
    mutating func finish() -> AudioChunk? {
        pending.isEmpty ? nil : take(pending.count)
    }

    private mutating func take(_ count: Int) -> AudioChunk {
        let chunk = AudioChunk(samples: Array(pending.prefix(count)), startSeconds: Double(emitted) / Double(Self.sampleRate))
        pending.removeFirst(count)
        emitted += count
        return chunk
    }

    /// The middle of the quietest window between 20 and 30 seconds; `samples` holds at least 30 s.
    private static func cutIndex(in samples: [Float]) -> Int {
        var quietest = minimum
        var lowest = Float.greatestFiniteMagnitude
        var start = minimum
        while start + window <= maximum {
            var energy: Float = 0
            for index in start..<(start + window) { energy += samples[index] * samples[index] }
            if energy < lowest {
                lowest = energy
                quietest = start
            }
            start += window
        }
        return quietest + window / 2
    }
}
