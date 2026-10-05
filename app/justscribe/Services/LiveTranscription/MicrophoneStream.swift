//
//  MicrophoneStream.swift
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

/// A microphone as a live audio source: its own capture session, separate from the one
/// dictation uses, so a live transcription and a dictation can share the microphone.
nonisolated final class MicrophoneStream: NSObject, LiveAudioSource, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let deviceID: String
    private let sink: LiveAudioSink
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.quassum.justscribe.live.microphone")
    /// Touched only on `queue`.
    private let converter = SampleRateConverter()

    init(deviceID: String, sink: @escaping LiveAudioSink) {
        self.deviceID = deviceID
        self.sink = sink
    }

    func start() throws {
        guard let device = AVCaptureDevice(uniqueID: deviceID) else { throw LiveAudioError.noMicrophone }
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw LiveAudioError.microphoneUnavailable
        }
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        session.beginConfiguration()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            throw LiveAudioError.microphoneUnavailable
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        session.startRunning()
        guard session.isRunning else { throw LiveAudioError.microphoneUnavailable }
    }

    func stop() {
        session.stopRunning()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              let buffers = PCMSampleConverter.channelBuffers(of: sampleBuffer) else { return }
        let mono = PCMSampleConverter.monoSamples(from: buffers, format: PCMFormat(asbd))
        let samples = converter.convert(mono, from: asbd.mSampleRate)
        if !samples.isEmpty { sink(samples) }
    }
}
