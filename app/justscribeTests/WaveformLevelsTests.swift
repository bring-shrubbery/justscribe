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
import Testing
@testable import justscribe

struct WaveformLevelsTests {

    @Test func silenceLeavesEveryBarFlat() {
        var levels = WaveformLevels()
        for _ in 0..<10 { levels.push(level: 0) }
        #expect(levels.bars == Array(repeating: 0, count: WaveformLevels.barCount))
    }

    @Test func roomNoiseIsBelowTheFloor() {
        var levels = WaveformLevels()
        for _ in 0..<10 { levels.push(level: WaveformLevels.noiseFloor - 0.05) }
        #expect(levels.bars.allSatisfy { $0 == 0 })
    }

    @Test func theNewestLevelIsTheCentreBarAndOlderOnesSpreadOutwards() {
        var levels = WaveformLevels()
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
        levels.push(level: 1)
        #expect(levels.bars[2] == 1)
        levels.push(level: 0)
        let afterOne = levels.bars[2]
        #expect(afterOne > 0 && afterOne < 1)
        levels.push(level: 0)
        #expect(levels.bars[2] < afterOne)
    }
}
