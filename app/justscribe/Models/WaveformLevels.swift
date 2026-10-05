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
struct WaveformLevels: Equatable {
    static let barCount = 5
    /// Below this much of the capture service's 0…1 level (0 at −60 dBFS) is room noise.
    static let noiseFloor: Float = 0.3
    /// How much of a bar's height survives a quiet sample: a bar falls slower than it rises,
    /// so a word does not flicker.
    static let decay: Float = 0.7

    /// Recent smoothed levels, newest last; one per distinct bar height.
    private(set) var recent: [Float]
    private var smoothed: Float = 0

    init() {
        recent = Array(repeating: 0, count: Self.barCount / 2 + 1)
    }

    /// Adds one sample of the capture service's level.
    mutating func push(level: Float) {
        let aboveFloor = max(0, min(1, (level - Self.noiseFloor) / (1 - Self.noiseFloor)))
        let cleaned = pow(aboveFloor, 0.7)
        smoothed = cleaned > smoothed ? cleaned : smoothed * Self.decay + cleaned * (1 - Self.decay)
        recent.removeFirst()
        recent.append(smoothed)
    }

    /// One height per bar, 0…1: the newest level in the middle, older ones towards the edges.
    var bars: [Float] {
        let half = Self.barCount / 2
        return (0..<Self.barCount).map { recent[recent.count - 1 - abs($0 - half)] }
    }
}
