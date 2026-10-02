//
//  AudioFileDecoderTests.swift
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

struct AudioFileDecoderTests {

    /// Writes `seconds` of a 440 Hz tone as a 44.1 kHz stereo WAV and returns its URL.
    private func makeWAV(seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("justscribe-\(UUID().uuidString).wav")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(seconds * 44_100)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        for channel in 0..<2 {
            let data = try #require(buffer.floatChannelData?[channel])
            for frame in 0..<Int(frames) { data[frame] = sinf(2 * .pi * 440 * Float(frame) / 44_100) * 0.5 }
        }
        try file.write(from: buffer)
        return url
    }

    private func readAll(_ decoder: AudioFileDecoder) async throws -> [Float] {
        var samples: [Float] = []
        while let next = try await decoder.next() { samples += next }
        return samples
    }

    @Test func aStereoFileDecodesToSixteenKilohertzMono() async throws {
        let url = try makeWAV(seconds: 3)
        defer { try? FileManager.default.removeItem(at: url) }
        let decoder = try await AudioFileDecoder.open(url)
        #expect(abs(decoder.duration - 3) < 0.05)
        let samples = try await readAll(decoder)
        #expect(abs(Double(samples.count) - 48_000) < 480)          // within 1%
        #expect((samples.map(abs).max() ?? 0) > 0.2)                // it is the tone, not silence
        #expect(try await decoder.next() == nil)                    // stays finished
    }

    @Test func theFileArrivesInBuffersOfUnderASecond() async throws {
        let url = try makeWAV(seconds: 3)
        defer { try? FileManager.default.removeItem(at: url) }
        let decoder = try await AudioFileDecoder.open(url)
        var buffers: [[Float]] = []
        while let next = try await decoder.next() { buffers.append(next) }
        // Observed for this WAV: five buffers of 8192 samples (0.512 s) and a last one of 7034.
        #expect(buffers.count > 1)                                  // streamed, not the whole file at once
        #expect(buffers.allSatisfy { !$0.isEmpty && $0.count <= 16_000 })   // none longer than a second
        #expect(abs(Double(buffers.map(\.count).reduce(0, +)) - 48_000) < 480)
    }

    @Test func nonFiniteSamplesBecomeSilence() {
        #expect(AudioFileDecoder.sanitized([0.5, .nan, -.infinity, .infinity, -0.25]) == [0.5, 0, 0, 0, -0.25])
        let finite: [Float] = [0, 0.1, -1, 1, 0.333]
        #expect(AudioFileDecoder.sanitized(finite) == finite)
    }

    @Test func aFileThatIsNotMediaIsNotReadable() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("justscribe-\(UUID().uuidString).txt")
        try "not audio".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: AudioFileError.notReadable) { _ = try await AudioFileDecoder.open(url) }
    }

    @Test func aMissingFileIsNotReadable() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("justscribe-missing-\(UUID().uuidString).m4a")
        await #expect(throws: AudioFileError.notReadable) { _ = try await AudioFileDecoder.open(url) }
    }

    @Test func everyErrorHasASentenceForTheWindow() {
        #expect(AudioFileError.notReadable.message == "JustScribe can't read this file")
        #expect(AudioFileError.noAudioTrack.message == "This file has no audio")
        #expect(AudioFileError.protectedContent.message == "This file is copy-protected and can't be transcribed")
    }
}
