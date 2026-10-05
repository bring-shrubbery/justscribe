//
//  SystemAudioTap.swift
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
import CoreAudio
import Foundation

/// What the other apps play, as a live audio source: a Core Audio process tap on every
/// process's output, read through a private aggregate device. macOS asks the user to allow
/// system audio recording the first time (Privacy & Security → Screen & System Audio
/// Recording); the tap plays audio on as normal and never mutes it.
nonisolated final class SystemAudioTap: LiveAudioSource, @unchecked Sendable {
    private let sink: LiveAudioSink
    private let queue = DispatchQueue(label: "com.quassum.justscribe.live.systemaudio")
    /// Touched only on `queue`.
    private let converter = SampleRateConverter()

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    init(sink: @escaping LiveAudioSink) {
        self.sink = sink
    }

    func start() throws {
        do {
            try startTap()
        } catch {
            stop()
            throw error
        }
    }

    private func startTap() throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "JustScribe Live Transcription"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var tap = AudioObjectID(kAudioObjectUnknown)
        try Self.check(AudioHardwareCreateProcessTap(description, &tap), "tap")
        tapID = tap

        var format = AudioStreamBasicDescription()
        try Self.read(kAudioTapPropertyFormat, of: tap, into: &format)
        guard format.mSampleRate > 0, format.mFormatID == kAudioFormatLinearPCM else {
            throw LiveAudioError.systemAudioUnavailable("unexpected audio format")
        }
        let pcmFormat = PCMFormat(format)
        let sampleRate = format.mSampleRate

        // The aggregate device is clocked by the default output device, and carries the tap.
        var outputDevice = AudioObjectID(kAudioObjectUnknown)
        try Self.read(kAudioHardwarePropertyDefaultOutputDevice, of: AudioObjectID(kAudioObjectSystemObject), into: &outputDevice)
        var outputUID: CFString = "" as CFString
        try Self.read(kAudioDevicePropertyDeviceUID, of: outputDevice, into: &outputUID)
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "JustScribe System Audio",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        var aggregate = AudioObjectID(kAudioObjectUnknown)
        try Self.check(AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate), "aggregate device")
        aggregateID = aggregate

        var proc: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, queue) { [weak self] _, inputData, _, _, _ in
            self?.deliver(inputData, format: pcmFormat, sampleRate: sampleRate)
        }
        try Self.check(status, "audio callback")
        procID = proc
        try Self.check(AudioDeviceStart(aggregate, proc), "start")
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    /// The tap's buffers (one per channel, or one interleaved) as 16 kHz mono, on `queue`.
    private func deliver(_ list: UnsafePointer<AudioBufferList>, format: PCMFormat, sampleRate: Double) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list)).map { buffer in
            guard let data = buffer.mData else { return Data() }
            return Data(bytes: data, count: Int(buffer.mDataByteSize))
        }
        let mono = PCMSampleConverter.monoSamples(from: buffers, format: format)
        let samples = converter.convert(mono, from: sampleRate)
        if !samples.isEmpty { sink(samples) }
    }

    private static func check(_ status: OSStatus, _ step: String) throws {
        guard status == noErr else { throw LiveAudioError.systemAudioUnavailable("\(step): error \(status)") }
    }

    private static func read<T>(_ selector: AudioObjectPropertySelector, of object: AudioObjectID, into value: inout T) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value), "property \(selector)")
    }
}
