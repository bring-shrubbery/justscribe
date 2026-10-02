//
//  AudioFileDecoder.swift
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

/// A file's audio as a stream of 16 kHz mono samples; a protocol so tests can stand in for a file.
/// Not tied to the main actor: decoding happens off it.
nonisolated protocol FileAudioSource: Sendable {
    /// The length of the audio in seconds.
    var duration: Double { get }
    /// The next stretch of samples, nil once the file has ended.
    func next() async throws -> [Float]?
}

nonisolated enum AudioFileError: Error, Equatable {
    case notReadable
    case noAudioTrack
    case protectedContent

    var message: String {
        switch self {
        case .notReadable: "JustScribe can't read this file"
        case .noAudioTrack: "This file has no audio"
        case .protectedContent: "This file is copy-protected and can't be transcribed"
        }
    }
}

/// Decodes the first audio track of any file AVFoundation can read to 16 kHz mono floats,
/// one buffer at a time, so the length of the file does not decide how much memory is used.
actor AudioFileDecoder: FileAudioSource {
    nonisolated let duration: Double
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private var finished = false

    /// `@concurrent` so the synchronous reader setup never runs on the caller's actor (the main
    /// actor when the window calls it); a plain async function here would inherit it.
    @concurrent static func open(_ url: URL) async throws -> AudioFileDecoder {
        let asset = AVURLAsset(url: url)
        let tracks: [AVAssetTrack]
        let seconds: Double
        do {
            if try await asset.load(.hasProtectedContent) { throw AudioFileError.protectedContent }
            tracks = try await asset.loadTracks(withMediaType: .audio)
            seconds = try await asset.load(.duration).seconds
        } catch let error as AudioFileError {
            throw error
        } catch {
            throw AudioFileError.notReadable
        }
        guard let track = tracks.first else {
            // A readable asset with no audio track; anything AVFoundation cannot open at all threw above.
            let hasAnyTrack = ((try? await asset.load(.tracks)) ?? []).isEmpty == false
            throw hasAnyTrack ? AudioFileError.noAudioTrack : AudioFileError.notReadable
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        do {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { throw AudioFileError.notReadable }
            reader.add(output)
            guard reader.startReading() else { throw AudioFileError.notReadable }
            return AudioFileDecoder(reader: reader, output: output, duration: seconds.isFinite ? seconds : 0)
        } catch let error as AudioFileError {
            throw error
        } catch {
            throw AudioFileError.notReadable
        }
    }

    private init(reader: AVAssetReader, output: AVAssetReaderTrackOutput, duration: Double) {
        self.reader = reader
        self.output = output
        self.duration = duration
    }

    func next() async throws -> [Float]? {
        while !finished {
            guard let sampleBuffer = output.copyNextSampleBuffer() else {
                finished = true
                if reader.status == .failed { throw AudioFileError.notReadable }
                return nil
            }
            guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            if length < MemoryLayout<Float>.size { continue }
            var samples = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            let status = samples.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes.count, destination: bytes.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { throw AudioFileError.notReadable }
            return Self.sanitized(samples)
        }
        return nil
    }

    /// The samples with anything that is not a finite number (a corrupt file can decode to NaN
    /// or infinity) replaced by silence, so it never reaches the speech model.
    nonisolated static func sanitized(_ samples: [Float]) -> [Float] {
        guard samples.contains(where: { !$0.isFinite }) else { return samples }
        return samples.map { $0.isFinite ? $0 : 0 }
    }
}
