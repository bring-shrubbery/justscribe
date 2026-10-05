//
//  WaveformLevels.swift
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

/// The bar heights of the listening waveform: a short, smoothed history of the microphone
/// level with the newest sample in the centre bar, so the bars pulse with speech instead of
/// scrolling past.
///
/// Microphones differ by tens of decibels in how loud speech comes through, so the bars are not
/// cut at fixed levels: a running floor (the quietest recent sample) and a running peak (the
/// loudest, slowly decaying) bracket the range, and a bar's height is where the sample falls
/// between them. Steady room noise sits on the floor and stays flat; a word reaches the top.
struct WaveformLevels: Equatable {
    static let barCount = 5
    /// The least range (in the capture service's 0…1 units, 0.1 ≈ 6 dB) the bars are scaled
    /// over, so silence is not stretched into a full-height flicker.
    static let minimumSpan: Float = 0.12
    /// How far the floor creeps up and the peak sinks per sample (20 samples a second), so the
    /// range re-adapts within seconds when the room or the microphone changes.
    static let floorRise: Float = 0.003
    static let peakFall: Float = 0.004
    /// How much of a bar's height survives a quiet sample: a bar falls slower than it rises,
    /// so a word does not flicker.
    static let decay: Float = 0.7

    /// Recent smoothed levels, newest last; one per distinct bar height.
    private(set) var recent: [Float]
    private var smoothed: Float = 0
    private var floor: Float = 1
    private var peak: Float = 0

    init() {
        recent = Array(repeating: 0, count: Self.barCount / 2 + 1)
    }

    /// Adds one sample of the capture service's level.
    mutating func push(level: Float) {
        floor = min(level, floor + Self.floorRise)
        peak = max(level, peak - Self.peakFall)
        let span = max(peak - floor, Self.minimumSpan)
        let scaled = max(0, min(1, (level - floor) / span))
        smoothed = scaled > smoothed ? scaled : smoothed * Self.decay + scaled * (1 - Self.decay)
        recent.removeFirst()
        recent.append(smoothed)
    }

    /// One height per bar, 0…1: the newest level in the middle, older ones towards the edges.
    var bars: [Float] {
        let half = Self.barCount / 2
        return (0..<Self.barCount).map { recent[recent.count - 1 - abs($0 - half)] }
    }
}
