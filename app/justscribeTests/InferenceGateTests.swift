//
//  InferenceGateTests.swift
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

@MainActor
struct InferenceGateTests {

    @Test func bodiesNeverOverlapAndRunInArrivalOrder() async {
        let gate = InferenceGate()
        var running = 0
        var maxRunning = 0
        var order: [Int] = []

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<5 {
                group.addTask { @MainActor in
                    await gate.run {
                        running += 1
                        maxRunning = max(maxRunning, running)
                        order.append(index)
                        try? await Task.sleep(for: .milliseconds(20))
                        running -= 1
                    }
                }
                // Let each task reach the gate before the next is added, so arrival order is 0…4.
                try? await Task.sleep(for: .milliseconds(2))
            }
        }
        #expect(maxRunning == 1)
        #expect(order == [0, 1, 2, 3, 4])
    }

    @Test func aThrowingBodyReleasesTheGate() async {
        struct Boom: Error {}
        let gate = InferenceGate()
        await #expect(throws: Boom.self) { try await gate.run { throw Boom() } }
        let value = await gate.run { 7 }
        #expect(value == 7)
    }
}
