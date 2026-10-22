//
//  DictationBridgeTests.swift
//  JustScribeKeyboard
//
//  Created by Antoni Silvestrovic on 22/10/2026.
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
import Testing
@testable import JustScribe

@MainActor
struct DictationBridgeTests {

    private func makeBridge() -> (DictationBridge, UserDefaults) {
        let suite = "DictationBridgeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (DictationBridge(defaults: defaults), defaults)
    }

    @Test func sessionIsLiveOnlyWhileTheHeartbeatIsFresh() {
        let (bridge, _) = makeBridge()
        #expect(!bridge.isSessionLive())
        bridge.publishHeartbeat(.now)
        #expect(bridge.isSessionLive())
        #expect(!bridge.isSessionLive(now: .now.addingTimeInterval(DictationBridge.heartbeatValidity + 1)))
        bridge.publishHeartbeat(nil)
        #expect(!bridge.isSessionLive())
    }

    @Test func resultIsInsertedOnce() throws {
        let (bridge, _) = makeBridge()
        bridge.publish(result: "Hello there")
        let result = try #require(bridge.pendingResult())
        #expect(result.text == "Hello there")
        bridge.markConsumed(result)
        #expect(bridge.pendingResult() == nil)
    }

    @Test func oldResultIsNeverInserted() {
        let (bridge, _) = makeBridge()
        bridge.publish(result: "Earlier")
        #expect(bridge.pendingResult(now: .now.addingTimeInterval(DictationBridge.resultValidity + 1)) == nil)
    }

    @Test func recordingClearsTheLastError() {
        let (bridge, _) = makeBridge()
        bridge.publish(error: "No microphone")
        #expect(bridge.errorMessage == "No microphone")
        bridge.publish(phase: .recording)
        #expect(bridge.phase == .recording)
        #expect(bridge.errorMessage == nil)
        #expect(bridge.recordingStarted != nil)
    }
}

struct TextSpacingTests {

    @Test func startOfFieldGetsNoSpace() {
        #expect(TextSpacing.insertion(of: "Hello", after: nil) == "Hello")
        #expect(TextSpacing.insertion(of: "Hello", after: "") == "Hello")
    }

    @Test func afterAWordGetsASpace() {
        #expect(TextSpacing.insertion(of: "world", after: "Hello") == " world")
        #expect(TextSpacing.insertion(of: "Next.", after: "Done.") == " Next.")
    }

    @Test func afterSpaceOrLineGetsNone() {
        #expect(TextSpacing.insertion(of: "world", after: "Hello ") == "world")
        #expect(TextSpacing.insertion(of: "world", after: "Hello\n") == "world")
    }

    @Test func punctuationAttachesToThePreviousWord() {
        #expect(TextSpacing.insertion(of: ", then", after: "First") == ", then")
    }

    @Test func emptyDictationInsertsNothing() {
        #expect(TextSpacing.insertion(of: "  ", after: "Hello") == "")
    }
}
