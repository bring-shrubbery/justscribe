//
//  AudioCaptureService.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
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
    private var inputSampleRate: Double = 44100
    private var recordingStartTime: Date?

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

        // Select first available device if none selected
        if selectedDevice == nil, let first = availableDevices.first {
            selectedDevice = first
        }
        #endif
    }

    func selectDevice(_ device: MicrophoneDevice) {
        selectedDevice = device
        if isRecording {
            stopRecording()
            startRecording()
        }
    }

    func selectDeviceByPriority(_ priorityList: [String]) {
        for deviceID in priorityList {
            if let device = availableDevices.first(where: { $0.id == deviceID && $0.isAvailable }) {
                selectDevice(device)
                return
            }
        }

        // Fall back to first available
        if let first = availableDevices.first(where: { $0.isAvailable }) {
            selectDevice(first)
        }
    }

    func startRecording() {
        guard !isRecording else { return }
        guard let device = selectedDevice else {
            print("No microphone selected")
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
            captureSession = AVCaptureSession()
            captureSession?.beginConfiguration()

            let input = try AVCaptureDeviceInput(device: avDevice)
            if captureSession?.canAddInput(input) == true {
                captureSession?.addInput(input)
            }

            audioOutput = AVCaptureAudioDataOutput()
            audioOutput?.setSampleBufferDelegate(self, queue: DispatchQueue(label: "audio.capture.queue"))

            if captureSession?.canAddOutput(audioOutput!) == true {
                captureSession?.addOutput(audioOutput!)
            }

            captureSession?.commitConfiguration()
            captureSession?.startRunning()

            audioBuffer.removeAll()
            recordingStartTime = Date()
            isRecording = true
        } catch {
            print("Failed to start recording: \(error)")
        }
        #endif
    }

    func stopRecording() {
        guard isRecording else { return }

        captureSession?.stopRunning()
        captureSession = nil
        audioOutput = nil
        isRecording = false
        currentAudioLevel = 0
        recordingDuration = Date().timeIntervalSince(recordingStartTime ?? Date())
        recordingStartTime = nil
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
        // Get the format description to determine sample rate and format
        if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
            let audioStreamBasicDesc = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
            if let asbd = audioStreamBasicDesc?.pointee {
                DispatchQueue.main.async {
                    if self.inputSampleRate != asbd.mSampleRate {
                        self.inputSampleRate = asbd.mSampleRate
                        print("Audio format - Sample rate: \(asbd.mSampleRate), Channels: \(asbd.mChannelsPerFrame), Bits: \(asbd.mBitsPerChannel), Format: \(asbd.mFormatID)")
                    }
                }
            }
        }

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

        guard let data = dataPointer else { return }

        // Get format info to determine how to interpret the data
        var floatSamples: [Float] = []

        if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee {

            let formatFlags = asbd.mFormatFlags
            let isFloat = (formatFlags & kAudioFormatFlagIsFloat) != 0
            let isSignedInt = (formatFlags & kAudioFormatFlagIsSignedInteger) != 0
            let bitsPerChannel = asbd.mBitsPerChannel
            let bytesPerSample = Int(asbd.mBytesPerFrame / asbd.mChannelsPerFrame)

            if isFloat && bitsPerChannel == 32 {
                // 32-bit float format (common on macOS)
                let sampleCount = length / 4
                floatSamples = [Float](repeating: 0, count: sampleCount)
                data.withMemoryRebound(to: Float.self, capacity: sampleCount) { floatPtr in
                    for i in 0..<sampleCount {
                        floatSamples[i] = floatPtr[i]
                    }
                }
            } else if isFloat && bitsPerChannel == 64 {
                // 64-bit float (rare, but handle it)
                let sampleCount = length / 8
                floatSamples = [Float](repeating: 0, count: sampleCount)
                data.withMemoryRebound(to: Double.self, capacity: sampleCount) { doublePtr in
                    for i in 0..<sampleCount {
                        floatSamples[i] = Float(doublePtr[i])
                    }
                }
            } else if bitsPerChannel == 16 {
                // 16-bit integer format (most common)
                let sampleCount = length / 2
                floatSamples = [Float](repeating: 0, count: sampleCount)
                if isSignedInt {
                    data.withMemoryRebound(to: Int16.self, capacity: sampleCount) { int16Ptr in
                        for i in 0..<sampleCount {
                            floatSamples[i] = Float(int16Ptr[i]) / Float(Int16.max)
                        }
                    }
                } else {
                    data.withMemoryRebound(to: UInt16.self, capacity: sampleCount) { uint16Ptr in
                        for i in 0..<sampleCount {
                            floatSamples[i] = (Float(uint16Ptr[i]) / Float(UInt16.max)) * 2.0 - 1.0
                        }
                    }
                }
            } else if bitsPerChannel == 24 {
                // 24-bit integer (professional audio)
                let sampleCount = length / 3
                floatSamples = [Float](repeating: 0, count: sampleCount)
                for i in 0..<sampleCount {
                    let offset = i * 3
                    // Little-endian 24-bit
                    let b0 = Int32(data[offset]) & 0xFF
                    let b1 = Int32(data[offset + 1]) & 0xFF
                    let b2 = Int32(data[offset + 2])
                    var value = (b2 << 16) | (b1 << 8) | b0
                    // Sign extend if needed
                    if isSignedInt && (value & 0x800000) != 0 {
                        value |= Int32(bitPattern: 0xFF000000)
                    }
                    floatSamples[i] = Float(value) / Float(0x7FFFFF)
                }
            } else if bitsPerChannel == 32 && !isFloat {
                // 32-bit integer format
                let sampleCount = length / 4
                floatSamples = [Float](repeating: 0, count: sampleCount)
                if isSignedInt {
                    data.withMemoryRebound(to: Int32.self, capacity: sampleCount) { int32Ptr in
                        for i in 0..<sampleCount {
                            floatSamples[i] = Float(int32Ptr[i]) / Float(Int32.max)
                        }
                    }
                } else {
                    data.withMemoryRebound(to: UInt32.self, capacity: sampleCount) { uint32Ptr in
                        for i in 0..<sampleCount {
                            floatSamples[i] = (Float(uint32Ptr[i]) / Float(UInt32.max)) * 2.0 - 1.0
                        }
                    }
                }
            } else {
                // Fallback: assume 16-bit signed PCM
                let sampleCount = length / 2
                floatSamples = [Float](repeating: 0, count: sampleCount)
                data.withMemoryRebound(to: Int16.self, capacity: sampleCount) { int16Ptr in
                    for i in 0..<sampleCount {
                        floatSamples[i] = Float(int16Ptr[i]) / Float(Int16.max)
                    }
                }
            }
        } else {
            // Fallback: assume 16-bit signed PCM
            let sampleCount = length / 2
            floatSamples = [Float](repeating: 0, count: sampleCount)
            data.withMemoryRebound(to: Int16.self, capacity: sampleCount) { int16Ptr in
                for i in 0..<sampleCount {
                    floatSamples[i] = Float(int16Ptr[i]) / Float(Int16.max)
                }
            }
        }

        // Calculate audio level
        let rms = sqrt(floatSamples.map { $0 * $0 }.reduce(0, +) / Float(max(floatSamples.count, 1)))
        let level = 20 * log10(max(rms, 0.0001))
        let normalizedLevel = max(0, min(1, (level + 60) / 60))

        DispatchQueue.main.async {
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
