//
//  AudioCaptureService.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
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
import AVFoundation
import Accelerate

@Observable
final class AudioCaptureService: NSObject {
    static let shared = AudioCaptureService()

    private(set) var isRecording = false
    private(set) var currentAudioLevel: Float = 0
    private(set) var availableDevices: [MicrophoneDevice] = []
    private(set) var selectedDevice: MicrophoneDevice?
    private(set) var recordingDuration: TimeInterval = 0

    private var captureSession: AVCaptureSession?
    private var audioOutput: AVCaptureAudioDataOutput?
    private var audioBuffer: [Float] = []
    /// The device's format as the capture delegate last saw it (for diagnostics).
    private(set) var inputSampleRate: Double = 44100
    private(set) var inputChannels: Int = 1
    private var recordingStartTime: Date?

    /// Whether the AVCaptureSession is prepared and running (mic hardware active)
    private var isSessionPrepared = false
    /// The device ID the current prepared session is using
    private var preparedDeviceID: String?
    /// Whether we are actively accumulating audio samples into the buffer
    private var isAccumulating = false

    // WhisperKit expects 16kHz audio
    private let targetSampleRate: Double = 16000

    var onAudioBuffer: (([Float]) -> Void)?

    override init() {
        super.init()
        refreshDevices()
    }

    func refreshDevices() {
        #if os(macOS)
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )

        availableDevices = discoverySession.devices.enumerated().map { index, device in
            MicrophoneDevice(from: device, priority: index)
        }

        // Until a recording picks by priority, prefer a microphone that is not a Bluetooth headset.
        if selectedDevice == nil {
            selectedDevice = MicrophoneDevice.preferred(in: availableDevices, priority: [], banned: [])
        }
        #endif
    }

    func selectDevice(_ device: MicrophoneDevice) {
        selectedDevice = device
        // If session is prepared for a different device, tear down and re-prepare
        if isSessionPrepared && preparedDeviceID != device.id {
            let wasAccumulating = isAccumulating
            teardownSession()
            prepareSession()
            if wasAccumulating {
                isAccumulating = true
                isRecording = true
            }
        }
    }

    /// Selects the microphone `MicrophoneDevice.preferred` picks from the saved priority,
    /// after refreshing the list: a headset connected since the last recording is otherwise
    /// unknown, or known only as the first device.
    func selectDeviceByPriority(_ priorityList: [String], excluding bannedIDs: [String] = []) {
        refreshDevices()
        if let device = MicrophoneDevice.preferred(in: availableDevices, priority: priorityList, banned: bannedIDs) {
            selectDevice(device)
        }
    }

    /// Prepares (creates & starts) the AVCaptureSession for the currently selected device.
    /// This is idempotent — calling it when already prepared for the same device is a no-op.
    func prepareSession() {
        guard !isSessionPrepared else { return }
        guard let device = selectedDevice else {
            print("No microphone selected, cannot prepare session")
            return
        }

        #if os(macOS)
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        guard let avDevice = discoverySession.devices.first(where: { $0.uniqueID == device.id }) else {
            print("Could not find AVCaptureDevice for \(device.name)")
            return
        }

        do {
            let session = AVCaptureSession()
            session.beginConfiguration()

            let input = try AVCaptureDeviceInput(device: avDevice)
            if session.canAddInput(input) {
                session.addInput(input)
            }

            let output = AVCaptureAudioDataOutput()
            output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "audio.capture.queue"))

            if session.canAddOutput(output) {
                session.addOutput(output)
            }

            session.commitConfiguration()
            session.startRunning()

            captureSession = session
            audioOutput = output
            isSessionPrepared = true
            preparedDeviceID = device.id
            print("Audio session prepared for device: \(device.name)")
        } catch {
            print("Failed to prepare audio session: \(error)")
        }
        #endif
    }

    /// Tears down the AVCaptureSession completely, releasing mic hardware.
    private func teardownSession() {
        captureSession?.stopRunning()
        captureSession = nil
        audioOutput = nil
        isSessionPrepared = false
        preparedDeviceID = nil
        isAccumulating = false
        isRecording = false
        currentAudioLevel = 0
        print("Audio session torn down")
    }

    func startRecording() {
        guard let device = selectedDevice else {
            print("No microphone selected")
            return
        }

        // If session is already prepared for the correct device, just reset buffer
        if isSessionPrepared && preparedDeviceID == device.id {
            audioBuffer.removeAll()
            recordingStartTime = Date()
            recordingDuration = 0
            isAccumulating = true
            isRecording = true
            print("Recording started (reusing prepared session)")
            return
        }

        // Need to prepare a new session (different device or first time)
        if isSessionPrepared {
            teardownSession()
        }

        prepareSession()

        guard isSessionPrepared else { return }

        audioBuffer.removeAll()
        recordingStartTime = Date()
        recordingDuration = 0
        isAccumulating = true
        isRecording = true
        print("Recording started (new session)")
    }

    func stopRecording() {
        guard isRecording else { return }

        isAccumulating = false
        isRecording = false
        currentAudioLevel = 0
        recordingDuration = Date().timeIntervalSince(recordingStartTime ?? Date())
        recordingStartTime = nil

        // Tear down session immediately to release mic hardware
        teardownSession()
        print("Recording stopped")
    }

    func getAudioBuffer() -> [Float] {
        // Resample to 16kHz if needed
        if inputSampleRate != targetSampleRate {
            return resample(audioBuffer, from: inputSampleRate, to: targetSampleRate)
        }
        return audioBuffer
    }

    func clearBuffer() {
        audioBuffer.removeAll()
        recordingDuration = 0
    }

    // MARK: - Resampling

    private func resample(_ samples: [Float], from inputRate: Double, to outputRate: Double) -> [Float] {
        let ratio = outputRate / inputRate
        let outputLength = Int(Double(samples.count) * ratio)

        guard outputLength > 0 else { return [] }

        var output = [Float](repeating: 0, count: outputLength)

        // Simple linear interpolation resampling
        for i in 0..<outputLength {
            let srcIndex = Double(i) / ratio
            let srcIndexInt = Int(srcIndex)
            let fraction = Float(srcIndex - Double(srcIndexInt))

            if srcIndexInt + 1 < samples.count {
                output[i] = samples[srcIndexInt] * (1 - fraction) + samples[srcIndexInt + 1] * fraction
            } else if srcIndexInt < samples.count {
                output[i] = samples[srcIndexInt]
            }
        }

        return output
    }
}

#if os(macOS)
extension AudioCaptureService: AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee else { return }

        DispatchQueue.main.async {
            self.inputChannels = Int(asbd.mChannelsPerFrame)
            if self.inputSampleRate != asbd.mSampleRate {
                self.inputSampleRate = asbd.mSampleRate
                print("Audio format - Sample rate: \(asbd.mSampleRate), Channels: \(asbd.mChannelsPerFrame), Bits: \(asbd.mBitsPerChannel), Format: \(asbd.mFormatID)")
            }
        }

        guard let channelBuffers = PCMSampleConverter.channelBuffers(of: sampleBuffer) else { return }

        // One sample per frame, channels averaged, non-finite values silenced.
        let floatSamples = PCMSampleConverter.monoSamples(from: channelBuffers, format: PCMFormat(asbd))

        // Calculate audio level
        let rms = sqrt(floatSamples.map { $0 * $0 }.reduce(0, +) / Float(max(floatSamples.count, 1)))
        let level = 20 * log10(max(rms, 0.0001))
        let normalizedLevel = max(0, min(1, (level + 60) / 60))

        DispatchQueue.main.async {
            // Discard samples when not actively recording
            guard self.isAccumulating else { return }

            self.currentAudioLevel = normalizedLevel

            // Update recording duration
            if let startTime = self.recordingStartTime {
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }

            // Append to buffer
            self.audioBuffer.append(contentsOf: floatSamples)
            self.onAudioBuffer?(floatSamples)
        }
    }
}
#endif
