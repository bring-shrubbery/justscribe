//
//  AudioCaptureService.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import Foundation
import AVFoundation
import Combine

@Observable
final class AudioCaptureService: NSObject {
    static let shared = AudioCaptureService()

    private(set) var isRecording = false
    private(set) var currentAudioLevel: Float = 0
    private(set) var availableDevices: [MicrophoneDevice] = []
    private(set) var selectedDevice: MicrophoneDevice?

    private var captureSession: AVCaptureSession?
    private var audioOutput: AVCaptureAudioDataOutput?
    private var audioBuffer: [Float] = []

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
        audioBuffer.removeAll()
    }

    func getAudioBuffer() -> [Float] {
        return audioBuffer
    }

    func clearBuffer() {
        audioBuffer.removeAll()
    }
}

#if os(macOS)
extension AudioCaptureService: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

        guard let data = dataPointer else { return }

        // Convert to float samples (assuming 16-bit PCM)
        let sampleCount = length / 2
        var floatSamples = [Float](repeating: 0, count: sampleCount)

        data.withMemoryRebound(to: Int16.self, capacity: sampleCount) { int16Ptr in
            for i in 0..<sampleCount {
                floatSamples[i] = Float(int16Ptr[i]) / Float(Int16.max)
            }
        }

        // Calculate audio level
        let rms = sqrt(floatSamples.map { $0 * $0 }.reduce(0, +) / Float(sampleCount))
        let level = 20 * log10(max(rms, 0.0001))
        let normalizedLevel = max(0, min(1, (level + 60) / 60))

        DispatchQueue.main.async {
            self.currentAudioLevel = normalizedLevel
        }

        // Append to buffer
        audioBuffer.append(contentsOf: floatSamples)
        onAudioBuffer?(floatSamples)
    }
}
#endif
