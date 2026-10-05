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

/// Cuts a stream of samples into chunks of 20 to 30 seconds (or the lengths given) for the
/// speech model. Each cut is placed in the quietest 100 ms between the minimum and the
/// maximum, so a word is rarely split. The chunks concatenated are exactly the input.
nonisolated struct AudioChunker {
    static let sampleRate = 16_000
    private static let window = sampleRate / 10

    private let minimum: Int
    private let maximum: Int
    private var pending: [Float] = []
    private var emitted = 0

    /// Chunks of `minimumSeconds` to `maximumSeconds`; the maximum is at least the minimum plus
    /// one cut window.
    init(minimumSeconds: Int = 20, maximumSeconds: Int = 30) {
        minimum = max(1, minimumSeconds) * Self.sampleRate
        maximum = max(maximumSeconds * Self.sampleRate, minimum + Self.window)
    }

    /// Adds samples and returns every chunk that is now complete.
    mutating func append(_ samples: [Float]) -> [AudioChunk] {
        pending += samples
        var chunks: [AudioChunk] = []
        while pending.count >= maximum {
            chunks.append(take(cutIndex(in: pending)))
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

    /// The middle of the quietest window between the minimum and the maximum; `samples` holds
    /// at least the maximum.
    private func cutIndex(in samples: [Float]) -> Int {
        let window = Self.window
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
