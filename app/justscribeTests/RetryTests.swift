//
//  RetryTests.swift
//  justscribeTests
//
//  Created by Antoni Silvestrovic on 24/01/2026.
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

struct RetryTests {
    struct Boom: Error, Equatable { let attempt: Int }

    @Test func succeedsOnALaterAttemptAndReturnsItsValue() async throws {
        var calls = 0
        let value = try await Retry.attempting(3, delay: .milliseconds(1)) {
            calls += 1
            if calls < 3 { throw Boom(attempt: calls) }
            return "loaded"
        }
        #expect(value == "loaded")
        #expect(calls == 3)
    }

    @Test func givesUpAfterTheLastAttemptWithTheLastError() async {
        var calls = 0
        await #expect(throws: Boom(attempt: 3)) {
            try await Retry.attempting(3, delay: .milliseconds(1)) {
                calls += 1
                throw Boom(attempt: calls)
            }
        }
        #expect(calls == 3)
    }

    @Test func aFirstSuccessNeedsNoRetry() async throws {
        var calls = 0
        _ = try await Retry.attempting(3, delay: .seconds(10)) { calls += 1 }
        #expect(calls == 1)
    }

    @MainActor @Test func theMenuSaysWhatTheModelIsDoing() {
        #expect(AppDelegate.modelStatusTitle(isLoaded: true, isLoading: false, failure: nil, hasModel: true, name: "Parakeet v3") == nil)
        #expect(AppDelegate.modelStatusTitle(isLoaded: false, isLoading: true, failure: nil, hasModel: true, name: "Parakeet v3") == "Loading Parakeet v3…")
        #expect(AppDelegate.modelStatusTitle(isLoaded: false, isLoading: false, failure: "x", hasModel: true, name: "Parakeet v3") == "The model didn't load — Try Again")
        #expect(AppDelegate.modelStatusTitle(isLoaded: false, isLoading: false, failure: nil, hasModel: true, name: "Parakeet v3") == "Load Parakeet v3")
        #expect(AppDelegate.modelStatusTitle(isLoaded: false, isLoading: false, failure: nil, hasModel: false, name: nil) == "No model — Open Settings…")
    }
}
