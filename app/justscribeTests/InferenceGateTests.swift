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

/// What the bodies run through the gate did, in order.
@MainActor
private final class Log {
    var order: [Int] = []
    var running = 0
    var maxRunning = 0
    var isHolding = false
}

@MainActor
struct InferenceGateTests {

    /// Yields until `condition` holds; false if it still does not after many turns. A bound on
    /// turns rather than a clock, so the tests do not depend on timing.
    private func yieldUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<10_000 {
            if condition() { return true }
            await Task.yield()
        }
        return condition()
    }

    /// Takes the gate and keeps it until the returned closure is called.
    private func hold(_ gate: InferenceGate, log: Log) async -> (release: () -> Void, task: Task<Void, Error>) {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            try await gate.run {
                log.isHolding = true
                for await _ in stream {}
            }
        }
        #expect(await yieldUntil { log.isHolding })
        return ({ continuation.finish() }, task)
    }

    /// Starts a request that records `index` and yields inside the gate, and waits until it
    /// has joined the queue, so arrival order is the order of the calls.
    private func enqueue(_ index: Int, on gate: InferenceGate, log: Log) async -> Task<Void, Error> {
        let queued = gate.queuedCount
        let task = Task {
            try await gate.run {
                log.running += 1
                log.maxRunning = max(log.maxRunning, log.running)
                log.order.append(index)
                await Task.yield()
                await Task.yield()
                log.running -= 1
            }
        }
        #expect(await yieldUntil { gate.queuedCount == queued + 1 })
        return task
    }

    @Test func bodiesNeverOverlapAndRunInArrivalOrder() async throws {
        let gate = InferenceGate()
        let log = Log()
        let holder = await hold(gate, log: log)
        var tasks: [Task<Void, Error>] = []
        for index in 0..<5 {
            tasks.append(await enqueue(index, on: gate, log: log))
        }
        holder.release()
        try await holder.task.value
        for task in tasks { try await task.value }
        #expect(log.maxRunning == 1)
        #expect(log.order == [0, 1, 2, 3, 4])
        #expect(gate.queuedCount == 0)
    }

    @Test func aThrowingBodyReleasesTheGate() async throws {
        struct Boom: Error {}
        let gate = InferenceGate()
        await #expect(throws: Boom.self) { try await gate.run { throw Boom() } }
        let value = try await gate.run { 7 }
        #expect(value == 7)
    }

    @Test func aCallerCancelledWhileQueuedThrowsAndTheOthersRunInOrder() async throws {
        let gate = InferenceGate()
        let log = Log()
        let holder = await hold(gate, log: log)
        let first = await enqueue(0, on: gate, log: log)
        let cancelled = await enqueue(1, on: gate, log: log)
        let last = await enqueue(2, on: gate, log: log)

        cancelled.cancel()
        // The caller is woken while the gate is still held, and leaves the queue.
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(gate.queuedCount == 2)

        holder.release()
        try await holder.task.value
        try await first.value
        try await last.value
        #expect(log.order == [0, 2])
        #expect(log.maxRunning == 1)
    }

    @Test func aCallerCancelledBeforeArrivingTakesNoPlaceInTheQueue() async throws {
        let gate = InferenceGate()
        let log = Log()
        let holder = await hold(gate, log: log)
        var ran = false
        let task = Task { try await gate.run { ran = true } }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(gate.queuedCount == 0)
        holder.release()
        try await holder.task.value
        #expect(!ran)
    }

    @Test func aCallerCancelledAfterBeingGrantedTheGateRunsAndReleasesIt() async throws {
        let gate = InferenceGate()
        let log = Log()
        // Its own holder, so the cancel comes after the gate is handed over and before the
        // waiter resumes: the order in which the cancel handler loses the race.
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        var bodyRan = false
        var bodySawCancel = false
        var waiter: Task<Void, Error>?
        let holder = Task {
            try await gate.run {
                log.isHolding = true
                for await _ in stream {}
            }
            // The gate has just been handed to the waiter; cancel it before it resumes.
            waiter?.cancel()
        }
        #expect(await yieldUntil { log.isHolding })
        waiter = Task {
            try await gate.run {
                bodyRan = true
                bodySawCancel = Task.isCancelled
            }
        }
        #expect(await yieldUntil { gate.queuedCount == 1 })

        continuation.finish()
        try await holder.value
        try await waiter?.value
        #expect(bodyRan)
        #expect(bodySawCancel)

        // The gate is free again: a later caller gets it. Were the gate still held, the caller
        // would wait for ever; it is cancelled instead, so the test fails rather than hangs.
        var laterRan = false
        let later = Task { try await gate.run { laterRan = true } }
        let ran = await yieldUntil { laterRan }
        if !ran { later.cancel() }
        _ = try? await later.value
        #expect(ran)
        #expect(gate.queuedCount == 0)
    }
}
