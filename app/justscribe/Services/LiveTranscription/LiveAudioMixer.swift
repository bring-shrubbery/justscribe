//
//  LiveAudioMixer.swift
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

/// Mixes the sources of a live transcription into the one recording that is kept with its
/// transcript. Each source's 16 kHz samples are lined up by count from the start, which is
/// where both begin, and summed. A source that falls more than `maximumLag` behind the others
/// (system audio can stall while nothing plays) is padded with silence, so the mix never
/// waits on it for long.
nonisolated struct LiveAudioMixer {
    static let maximumLag = 2 * AudioChunker.sampleRate

    private var pending: [LiveAudioKind: [Float]]

    init(kinds: Set<LiveAudioKind>) {
        pending = Dictionary(uniqueKeysWithValues: kinds.map { ($0, []) })
    }

    /// Adds a source's samples and returns the mix that is now complete.
    mutating func append(_ samples: [Float], from kind: LiveAudioKind) -> [Float] {
        guard pending[kind] != nil else { return [] }
        if pending.count == 1 { return samples }
        pending[kind]! += samples
        let longest = pending.values.map(\.count).max() ?? 0
        for key in pending.keys where pending[key]!.count < longest - Self.maximumLag {
            pending[key]! += [Float](repeating: 0, count: longest - Self.maximumLag - pending[key]!.count)
        }
        return take(pending.values.map(\.count).min() ?? 0)
    }

    /// The rest, once every source has stopped; shorter sources are padded with silence.
    mutating func finish() -> [Float] {
        let longest = pending.values.map(\.count).max() ?? 0
        for key in pending.keys {
            pending[key]! += [Float](repeating: 0, count: longest - pending[key]!.count)
        }
        return take(longest)
    }

    private mutating func take(_ count: Int) -> [Float] {
        guard count > 0 else { return [] }
        var mix = [Float](repeating: 0, count: count)
        for key in pending.keys {
            let source = pending[key]!
            for index in 0..<count { mix[index] += source[index] }
            pending[key]!.removeFirst(count)
        }
        for index in 0..<count { mix[index] = max(-1, min(1, mix[index])) }
        return mix
    }
}
