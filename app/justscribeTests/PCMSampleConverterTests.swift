//
//  PCMSampleConverterTests.swift
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

struct PCMSampleConverterTests {

    private func bytes<T>(_ values: [T]) -> Data {
        values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private let stereoFloatPlanar = PCMFormat(isFloat: true, isSignedInteger: false, bitsPerChannel: 32,
                                              channels: 2, isNonInterleaved: true)

    @Test func separateChannelPlanesAreAveragedIntoOneSamplePerFrame() {
        let left: [Float] = [0.2, 0.4, -0.6]
        let right: [Float] = [0.0, 0.2, -0.2]
        let mono = PCMSampleConverter.monoSamples(from: [bytes(left), bytes(right)], format: stereoFloatPlanar)
        #expect(mono.count == 3)
        #expect(abs(mono[0] - 0.1) < 1e-6 && abs(mono[1] - 0.3) < 1e-6 && abs(mono[2] + 0.4) < 1e-6)
    }

    @Test func interleavedChannelsAreAveragedIntoOneSamplePerFrame() {
        let format = PCMFormat(isFloat: true, isSignedInteger: false, bitsPerChannel: 32,
                               channels: 2, isNonInterleaved: false)
        let mono = PCMSampleConverter.monoSamples(from: [bytes([Float(0.2), 0.0, 0.4, 0.2])], format: format)
        #expect(mono.count == 2)
        #expect(abs(mono[0] - 0.1) < 1e-6 && abs(mono[1] - 0.3) < 1e-6)
    }

    @Test func aTrailingPartialFrameIsDropped() {
        let format = PCMFormat(isFloat: true, isSignedInteger: false, bitsPerChannel: 32,
                               channels: 2, isNonInterleaved: false)
        let mono = PCMSampleConverter.monoSamples(from: [bytes([Float(0.2), 0.4, 0.6])], format: format)
        #expect(mono.count == 1)
    }

    @Test func planesOfDifferentLengthsUseTheShorterOne() {
        let mono = PCMSampleConverter.monoSamples(from: [bytes([Float(0.2), 0.4]), bytes([Float(0.2)])],
                                                  format: stereoFloatPlanar)
        #expect(mono.count == 1)
    }

    @Test func nonFiniteSamplesBecomeSilence() {
        let format = PCMFormat(isFloat: true, isSignedInteger: false, bitsPerChannel: 32,
                               channels: 1, isNonInterleaved: false)
        let mono = PCMSampleConverter.monoSamples(from: [bytes([Float(0.5), .nan, .infinity, -.infinity])],
                                                  format: format)
        #expect(mono == [0.5, 0, 0, 0])
    }

    @Test func aNonFiniteSampleInOneChannelSilencesOnlyThatChannel() {
        let mono = PCMSampleConverter.monoSamples(from: [bytes([Float.nan]), bytes([Float(0.4)])],
                                                  format: stereoFloatPlanar)
        #expect(mono.count == 1 && abs(mono[0] - 0.2) < 1e-6)
    }

    @Test func signedSixteenBitIsScaledToUnitRange() {
        let format = PCMFormat(isFloat: false, isSignedInteger: true, bitsPerChannel: 16,
                               channels: 1, isNonInterleaved: false)
        let mono = PCMSampleConverter.monoSamples(from: [bytes([Int16.max, 0, -Int16.max])], format: format)
        #expect(mono == [1, 0, -1])
    }

    @Test func signedTwentyFourBitIsSignExtended() {
        let format = PCMFormat(isFloat: false, isSignedInteger: true, bitsPerChannel: 24,
                               channels: 1, isNonInterleaved: false)
        // 0x7FFFFF (max) and 0x800001 (-max), little-endian.
        let mono = PCMSampleConverter.monoSamples(from: [Data([0xFF, 0xFF, 0x7F, 0x01, 0x00, 0x80])], format: format)
        #expect(mono == [1, -1])
    }

    @Test func noBuffersGiveNoSamples() {
        #expect(PCMSampleConverter.monoSamples(from: [], format: stereoFloatPlanar).isEmpty)
    }

    @Test func theFormatIsReadFromAStreamDescription() {
        // What a two-channel USB receiver delivers through AVCaptureAudioDataOutput.
        var asbd = AudioStreamBasicDescription()
        asbd.mSampleRate = 48000
        asbd.mFormatID = kAudioFormatLinearPCM
        asbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved
        asbd.mChannelsPerFrame = 2
        asbd.mBitsPerChannel = 32
        asbd.mBytesPerFrame = 4
        #expect(PCMFormat(asbd) == stereoFloatPlanar)
    }
}
