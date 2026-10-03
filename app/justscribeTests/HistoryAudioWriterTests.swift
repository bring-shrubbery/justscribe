//
//  HistoryAudioWriterTests.swift
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

import AVFoundation
import Foundation
import Testing
@testable import justscribe

@Suite(.timeLimit(.minutes(1)))
struct HistoryAudioWriterTests {

    private func tone(seconds: Double) -> [Float] {
        (0..<Int(seconds * 16_000)).map { sinf(2 * .pi * 440 * Float($0) / 16_000) * 0.5 }
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("justscribe-history-\(UUID().uuidString).m4a")
    }

    @Test func aRecordingRoundTripsThroughAAC() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try await HistoryAudioWriter.write(samples: tone(seconds: 3), to: url)
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        #expect(size > 1_000 && size < 60_000)   // ~38 kB for 3 s (~13 kB AAC audio plus AVAudioFile's fixed ~23.5 kB `free` atom), far from raw 192 kB

        // Read back through AVAudioFile rather than AudioFileDecoder: on the CI runner's VM a
        // third concurrent AVAssetReader (the decoder tests run two) deadlocks CoreMedia.
        let samples = try Self.decode(url)
        #expect(abs(Double(samples.count) - 48_000) < 48_000 * 0.02)
        #expect((samples.map(abs).max() ?? 0) > 0.2)
    }

    /// The file's samples through AudioToolbox, converted to the file's processing format.
    private static func decode(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let frames = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else { return [] }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    @Test func emptySamplesAreRefused() async {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: HistoryAudioWriter.WriteError.self) { try await HistoryAudioWriter.write(samples: [], to: url) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aFailedWriteLeavesNoFile() async {
        // A directory that does not exist: the file cannot be created.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("justscribe-missing-\(UUID().uuidString)")
            .appendingPathComponent("a.m4a")
        await #expect(throws: Error.self) { try await HistoryAudioWriter.write(samples: tone(seconds: 1), to: url) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
