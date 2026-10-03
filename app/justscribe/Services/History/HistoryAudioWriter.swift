//
//  HistoryAudioWriter.swift
//  justscribe
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

/// Writes a dictation's 16 kHz mono samples as a small AAC file for history. Encoding is
/// `@concurrent`: it must never run on the main actor.
nonisolated enum HistoryAudioWriter {
    static let sampleRate = 16_000.0
    static let bitRate = 48_000

    enum WriteError: Error { case noSamples, formatUnavailable }

    @concurrent static func write(samples: [Float], to url: URL) async throws {
        guard !samples.isEmpty else { throw WriteError.noSamples }
        guard let pcmFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw WriteError.formatUnavailable
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: bitRate,
        ]
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            // Write in chunks the encoder is comfortable with.
            let chunk = 16_384
            var index = 0
            while index < samples.count {
                let count = min(chunk, samples.count - index)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: AVAudioFrameCount(count)),
                      let channel = buffer.floatChannelData?[0] else { throw WriteError.formatUnavailable }
                samples.withUnsafeBufferPointer { source in
                    channel.update(from: source.baseAddress! + index, count: count)
                }
                buffer.frameLength = AVAudioFrameCount(count)
                try file.write(from: buffer)
                index += count
            }
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        // AVAudioFile finishes the file when it is released; it goes out of scope above.
    }
}
