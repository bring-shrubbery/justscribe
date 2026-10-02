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

import Foundation
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

    // MARK: - Leftover temporary audio

    /// A directory of its own under the temporary directory, removed afterwards.
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeakerDiarizationServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func leftoverAudioIsRemovedAndNothingElse() throws {
        let fileManager = FileManager.default
        let directory = try makeDirectory()
        defer { try? fileManager.removeItem(at: directory) }
        let leftovers = ["fluidaudio-streaming-\(UUID().uuidString).raw", "fluidaudio-streaming-x.raw"]
        let others = [
            "fluidaudio-streaming-x.wav", "fluidaudio-streaming-x", "streaming-x.raw",
            "my-fluidaudio-streaming-x.raw", "notes.txt",
        ]
        for name in leftovers + others {
            try Data([1, 2, 3]).write(to: directory.appendingPathComponent(name))
        }
        let folder = "fluidaudio-streaming-folder.raw"
        try fileManager.createDirectory(at: directory.appendingPathComponent(folder), withIntermediateDirectories: false)

        SpeakerDiarizationService.removeLeftoverAudio(in: directory)

        let remaining = try fileManager.contentsOfDirectory(atPath: directory.path)
        #expect(Set(remaining) == Set(others + [folder]))
    }

    @Test func aMissingDirectoryIsLeftAlone() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeakerDiarizationServiceTests-missing-\(UUID().uuidString)", isDirectory: true)
        SpeakerDiarizationService.removeLeftoverAudio(in: directory)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}

/// What the fake passes and sweeps did, in order.
@MainActor
private final class PassLog {
    var events: [String] = []
}

@MainActor
struct SpeakerPassSerialisationTests {
    struct Boom: Error {}

    /// Yields until `condition` holds; false if it still does not after many turns.
    private func yieldUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<10_000 {
            if condition() { return true }
            await Task.yield()
        }
        return condition()
    }

    /// A pass that logs its start, waits for `release` if given, and logs its end.
    private func pass(
        _ name: String, gate: InferenceGate, log: PassLog, release: AsyncStream<Void>? = nil, fails: Bool = false
    ) -> Task<Void, Error> {
        Task {
            try await SpeakerDiarizationService.runPass(on: gate, sweep: { log.events.append("sweep") }) {
                log.events.append("\(name) start")
                if let release { for await _ in release {} }
                await Task.yield()
                log.events.append("\(name) end")
                if fails { throw Boom() }
            }
        }
    }

    @Test func twoOverlappingPassesRunOneAfterTheOtherInOrder() async throws {
        let gate = InferenceGate()
        let log = PassLog()
        let (release, finish) = AsyncStream<Void>.makeStream()
        let first = pass("A", gate: gate, log: log, release: release)
        #expect(await yieldUntil { log.events.contains("A start") })
        let second = pass("B", gate: gate, log: log)
        #expect(await yieldUntil { gate.queuedCount == 1 })
        #expect(log.events == ["sweep", "A start"])

        finish.finish()
        try await first.value
        try await second.value
        #expect(log.events == ["sweep", "A start", "A end", "sweep", "B start", "B end"])
    }

    @Test func aPassCancelledWhileWaitingDoesNotRun() async throws {
        let gate = InferenceGate()
        let log = PassLog()
        let (release, finish) = AsyncStream<Void>.makeStream()
        let first = pass("A", gate: gate, log: log, release: release)
        #expect(await yieldUntil { log.events.contains("A start") })
        let second = pass("B", gate: gate, log: log)
        #expect(await yieldUntil { gate.queuedCount == 1 })

        second.cancel()
        await #expect(throws: CancellationError.self) { try await second.value }
        finish.finish()
        try await first.value
        #expect(log.events == ["sweep", "A start", "A end"])
        #expect(gate.queuedCount == 0)
    }

    @Test func aPassThatThrowsIsSweptAfterAndTheNextOneRuns() async throws {
        let gate = InferenceGate()
        let log = PassLog()
        let failing = pass("A", gate: gate, log: log, fails: true)
        await #expect(throws: Boom.self) { try await failing.value }
        try await pass("B", gate: gate, log: log).value
        #expect(log.events == ["sweep", "A start", "A end", "sweep", "sweep", "B start", "B end"])
    }
}

