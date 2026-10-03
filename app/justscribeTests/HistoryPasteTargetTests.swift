//
//  HistoryPasteTargetTests.swift
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

@Suite(.timeLimit(.minutes(1)))
struct HistoryPasteTargetTests {

    @Test func pastesIntoTheAppThatWasInFront() {
        let decision = HistoryPasteTarget.decide(previousApp: "com.apple.TextEdit", ownBundleID: "com.quassum.justscribe", isStillRunning: true)
        #expect(decision == .paste(into: "com.apple.TextEdit"))
    }

    @Test func fallsBackToCopyWhenThePreviousAppIsItself() {
        let decision = HistoryPasteTarget.decide(previousApp: "com.quassum.justscribe", ownBundleID: "com.quassum.justscribe", isStillRunning: true)
        #expect(decision == .copyOnly)
    }

    @Test func fallsBackToCopyWhenThereWasNoPreviousAppOrItQuit() {
        #expect(HistoryPasteTarget.decide(previousApp: nil, ownBundleID: "x", isStillRunning: true) == .copyOnly)
        #expect(HistoryPasteTarget.decide(previousApp: "com.apple.Notes", ownBundleID: "x", isStillRunning: false) == .copyOnly)
    }
}
