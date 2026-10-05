//
//  PCMSampleConverter.swift
//  justscribe
//
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
import CoreMedia

/// The parts of a linear PCM stream description needed to turn its bytes into samples.
nonisolated struct PCMFormat: Equatable, Sendable {
    var isFloat: Bool
    var isSignedInteger: Bool
    var bitsPerChannel: Int
    var channels: Int
    /// Each channel arrives in its own buffer (a "plane") instead of alternating in one.
    var isNonInterleaved: Bool

    init(isFloat: Bool, isSignedInteger: Bool, bitsPerChannel: Int, channels: Int, isNonInterleaved: Bool) {
        self.isFloat = isFloat
        self.isSignedInteger = isSignedInteger
        self.bitsPerChannel = bitsPerChannel
        self.channels = channels
        self.isNonInterleaved = isNonInterleaved
    }

    init(_ asbd: AudioStreamBasicDescription) {
        self.init(isFloat: asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  isSignedInteger: asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0,
                  bitsPerChannel: Int(asbd.mBitsPerChannel),
                  channels: max(Int(asbd.mChannelsPerFrame), 1),
                  isNonInterleaved: asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0)
    }
}

/// Turns captured PCM buffers into mono samples in -1...1.
///
/// A microphone can deliver several channels, either alternating in one buffer or as one buffer
/// per channel. Every channel is decoded and the channels are averaged, so one frame of audio
/// gives exactly one sample. Anything that is not a finite number becomes silence: a single NaN
/// would otherwise poison the whole recording for the speech model.
nonisolated enum PCMSampleConverter {

    static func monoSamples(from buffers: [Data], format: PCMFormat) -> [Float] {
        let planes: [[Float]]
        if format.isNonInterleaved {
            planes = buffers.map { decode($0, format) }
        } else {
            guard let buffer = buffers.first else { return [] }
            let interleaved = decode(buffer, format)
            let channels = format.channels
            let frames = interleaved.count / channels
            planes = (0..<channels).map { channel in
                (0..<frames).map { interleaved[$0 * channels + channel] }
            }
        }
        guard let frames = planes.map(\.count).min(), frames > 0 else { return [] }
        if planes.count == 1 { return planes[0] }

        var mono = [Float](repeating: 0, count: frames)
        for plane in planes {
            for i in 0..<frames { mono[i] += plane[i] }
        }
        let scale = 1 / Float(planes.count)
        for i in 0..<frames { mono[i] *= scale }
        return mono
    }

    /// Every sample in `data`, in order, with non-finite values replaced by 0.
    private static func decode(_ data: Data, _ format: PCMFormat) -> [Float] {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> [Float] in
            func read<T>(_ type: T.Type, _ convert: (T) -> Float) -> [Float] {
                let size = MemoryLayout<T>.size
                return (0..<(raw.count / size)).map { convert(raw.loadUnaligned(fromByteOffset: $0 * size, as: T.self)) }
            }
            let samples: [Float]
            switch (format.isFloat, format.bitsPerChannel) {
            case (true, 32):
                samples = read(Float.self) { $0 }
            case (true, 64):
                samples = read(Double.self) { Float($0) }
            case (false, 24):
                samples = (0..<(raw.count / 3)).map { i in
                    let o = i * 3
                    var value = Int32(raw[o]) | Int32(raw[o + 1]) << 8 | Int32(raw[o + 2]) << 16
                    if format.isSignedInteger && value & 0x800000 != 0 { value |= Int32(bitPattern: 0xFF000000) }
                    return format.isSignedInteger ? Float(value) / Float(0x7FFFFF) : Float(value) / Float(0xFFFFFF) * 2 - 1
                }
            case (false, 32):
                samples = format.isSignedInteger
                    ? read(Int32.self) { Float($0) / Float(Int32.max) }
                    : read(UInt32.self) { Float($0) / Float(UInt32.max) * 2 - 1 }
            case (false, 16) where !format.isSignedInteger:
                samples = read(UInt16.self) { Float($0) / Float(UInt16.max) * 2 - 1 }
            default:
                // 16-bit signed, and the fallback for anything unrecognised.
                samples = read(Int16.self) { Float($0) / Float(Int16.max) }
            }
            return samples.map { $0.isFinite ? $0 : 0 }
        }
    }
}

extension PCMSampleConverter {
    /// The sample buffer's audio as one `Data` per buffer: one per channel when the channels
    /// arrive separately, otherwise one. Read through an AudioBufferList because the block buffer
    /// behind a multi-channel capture is not contiguous: reading it as one run of bytes from its
    /// first pointer runs past the first channel into unrelated memory.
    static func channelBuffers(of sampleBuffer: CMSampleBuffer) -> [Data]? {
        var sizeNeeded = 0
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: &sizeNeeded, bufferListOut: nil, bufferListSize: 0,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil
        ) == noErr, sizeNeeded > 0 else { return nil }

        let raw = UnsafeMutableRawPointer.allocate(byteCount: sizeNeeded,
                                                   alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        var blockBuffer: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: list, bufferListSize: sizeNeeded,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: &blockBuffer
        ) == noErr else { return nil }

        // `blockBuffer` keeps the memory alive while the bytes are copied out.
        return withExtendedLifetime(blockBuffer) {
            UnsafeMutableAudioBufferListPointer(list).map { buffer in
                guard let data = buffer.mData else { return Data() }
                return Data(bytes: data, count: Int(buffer.mDataByteSize))
            }
        }
    }
}
