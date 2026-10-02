//
//  SpeakerDiarizationServiceTests.swift
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

struct SpeakerDiarizationServiceTests {

    @Test func segmentsBecomeTurnsInTimeOrder() {
        let turns = SpeakerDiarizationService.turns(fromSegments: [
            (speaker: "S2", start: 5.5, end: 9.0),
            (speaker: "S1", start: 0.25, end: 5.5),
        ])
        #expect(turns == [
            SpeakerTurn(speaker: "S1", start: 0.25, end: 5.5),
            SpeakerTurn(speaker: "S2", start: 5.5, end: 9.0),
        ])
    }

    @Test func emptyAndBackwardsSegmentsAreDropped() {
        let turns = SpeakerDiarizationService.turns(fromSegments: [
            (speaker: "S1", start: 2, end: 2),
            (speaker: "S1", start: 4, end: 3),
            (speaker: "S1", start: 5, end: 6),
        ])
        #expect(turns == [SpeakerTurn(speaker: "S1", start: 5, end: 6)])
    }
}
