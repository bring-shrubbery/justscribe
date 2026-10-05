//
//  LiveAudioSource.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 05/10/2026.
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

/// Where a live transcription's audio comes from.
nonisolated enum LiveAudioKind: Hashable, Sendable, CaseIterable {
    case microphone
    /// What the other apps play: a call's far end, a video, a recording.
    case systemAudio
}

/// Receives 16 kHz mono samples as they are captured, on the source's own queue.
typealias LiveAudioSink = @Sendable ([Float]) -> Void

/// Makes the source for `kind` that feeds `sink`; the app's makes the real microphone and
/// system-audio sources, tests make fakes.
typealias LiveAudioSourceFactory = @MainActor (LiveAudioKind, @escaping LiveAudioSink) throws -> any LiveAudioSource

/// A running capture of one kind of audio, delivering 16 kHz mono samples to its sink until
/// stopped. Starting may fail: a missing microphone, or system audio the user has not allowed.
nonisolated protocol LiveAudioSource: AnyObject, Sendable {
    func start() throws
    func stop()
}

nonisolated enum LiveAudioError: LocalizedError, Equatable {
    case noMicrophone
    case microphoneUnavailable
    case systemAudioUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .noMicrophone:
            "No microphone is available"
        case .microphoneUnavailable:
            "The microphone could not be started"
        case .systemAudioUnavailable(let detail):
            "System audio could not be recorded (\(detail)). Check Privacy & Security → Screen & System Audio Recording in System Settings."
        }
    }
}

/// Resamples mono audio to 16 kHz for the speech model, keeping the converter's state between
/// calls so a stream handed over piecewise comes out continuous. Not thread-safe: use it from
/// one queue.
nonisolated final class SampleRateConverter {
    static let outputRate = 16_000.0

    private let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: outputRate, channels: 1, interleaved: false)!
    private var converter: AVAudioConverter?
    private var inputRate: Double = 0

    /// `samples`, mono at `rate`, as 16 kHz mono. Audio already at 16 kHz passes through.
    func convert(_ samples: [Float], from rate: Double) -> [Float] {
        guard !samples.isEmpty, rate > 0 else { return [] }
        if rate == Self.outputRate { return samples }
        if converter == nil || inputRate != rate {
            guard let inputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
                  let made = AVAudioConverter(from: inputFormat, to: outputFormat) else { return [] }
            converter = made
            inputRate = rate
        }
        guard let converter,
              let input = AVAudioPCMBuffer(pcmFormat: converter.inputFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = input.floatChannelData?[0] else { return [] }
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        input.frameLength = AVAudioFrameCount(samples.count)

        let capacity = AVAudioFrameCount(Double(samples.count) * Self.outputRate / rate) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return [] }
        var handedOver = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if handedOver {
                outStatus.pointee = .noDataNow
                return nil
            }
            handedOver = true
            outStatus.pointee = .haveData
            return input
        }
        guard status != .error, let data = output.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(output.frameLength)))
    }
}
