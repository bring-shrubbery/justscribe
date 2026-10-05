//
//  WaveformLevelsTests.swift
//  justscribeTests
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

import Testing
@testable import justscribe

struct WaveformLevelsTests {

    @Test func silenceLeavesEveryBarFlat() {
        var levels = WaveformLevels()
        for _ in 0..<10 { levels.push(level: 0) }
        #expect(levels.bars == Array(repeating: 0, count: WaveformLevels.barCount))
    }

    @Test func steadyRoomNoiseStaysFlat() {
        var levels = WaveformLevels()
        for _ in 0..<40 { levels.push(level: 0.35) }
        #expect(levels.bars.allSatisfy { $0 == 0 })
    }

    @Test func aQuietMicrophoneStillFillsTheBars() {
        // Speech that only reaches 0.4 on a mic whose silence sits at 0.25.
        var levels = WaveformLevels()
        for _ in 0..<20 { levels.push(level: 0.25) }
        levels.push(level: 0.4)
        #expect(levels.bars[2] == 1)
    }

    @Test func theRangeFollowsTheLoudestRecentSample() {
        var levels = WaveformLevels()
        for _ in 0..<20 { levels.push(level: 0.2) }
        levels.push(level: 0.9)
        // Half-way between the floor and the peak settles at a half-height bar.
        for _ in 0..<10 { levels.push(level: 0.55) }
        #expect(abs(levels.bars[2] - 0.5) < 0.1)
    }

    @Test func theNewestLevelIsTheCentreBarAndOlderOnesSpreadOutwards() {
        var levels = WaveformLevels()
        // Set the range (0.1 to 1) and let the bars fall back, then ramp up.
        for _ in 0..<20 { levels.push(level: 0.1) }
        levels.push(level: 1)
        for _ in 0..<10 { levels.push(level: 0.1) }
        levels.push(level: 0.4)
        levels.push(level: 0.7)
        levels.push(level: 1)
        let bars = levels.bars
        #expect(bars.count == 5)
        #expect(bars[2] == 1)
        #expect(bars[1] == bars[3])
        #expect(bars[0] == bars[4])
        #expect(bars[2] > bars[1] && bars[1] > bars[0])
    }

    @Test func aBarRisesAtOnceAndFallsGradually() {
        var levels = WaveformLevels()
        for _ in 0..<20 { levels.push(level: 0.1) }
        levels.push(level: 1)
        #expect(levels.bars[2] == 1)
        levels.push(level: 0.1)
        let afterOne = levels.bars[2]
        #expect(afterOne > 0 && afterOne < 1)
        levels.push(level: 0.1)
        #expect(levels.bars[2] < afterOne)
    }
}
