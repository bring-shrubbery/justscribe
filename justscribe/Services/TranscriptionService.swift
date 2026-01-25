//
//  TranscriptionService.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import Foundation
import Combine

// Note: This service will use WhisperKit once added via SPM.
// For now, this is a placeholder implementation.

@Observable
final class TranscriptionService {
    static let shared = TranscriptionService()

    private(set) var state: TranscriptionState = .idle
    private(set) var currentTranscription: String = ""
    private(set) var isModelLoaded = false
    private(set) var loadedModelID: String?

    var onTranscriptionUpdate: ((String) -> Void)?
    var onTranscriptionComplete: ((String) -> Void)?

    enum TranscriptionState: Equatable {
        case idle
        case loadingModel
        case listening
        case processing
        case completed
        case error(String)

        static func == (lhs: TranscriptionState, rhs: TranscriptionState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle),
                 (.loadingModel, .loadingModel),
                 (.listening, .listening),
                 (.processing, .processing),
                 (.completed, .completed):
                return true
            case (.error(let lhsMsg), .error(let rhsMsg)):
                return lhsMsg == rhsMsg
            default:
                return false
            }
        }
    }

    private init() {}

    // MARK: - Model Management

    func loadModel(id: String, from path: URL) async throws {
        state = .loadingModel

        // Will be implemented with WhisperKit
        // let whisper = try await WhisperKit(modelFolder: path.path)

        // Simulate model loading
        try await Task.sleep(for: .seconds(1))

        loadedModelID = id
        isModelLoaded = true
        state = .idle
    }

    func unloadModel() {
        isModelLoaded = false
        loadedModelID = nil
        state = .idle
    }

    // MARK: - Transcription

    func startTranscription() {
        guard isModelLoaded else {
            state = .error(TranscriptionError.modelNotLoaded.localizedDescription)
            return
        }

        state = .listening
        currentTranscription = ""
    }

    func stopTranscription() async -> String {
        guard state == .listening else { return currentTranscription }

        state = .processing

        // Will be implemented with WhisperKit
        // Process the audio buffer from AudioCaptureService
        _ = AudioCaptureService.shared.getAudioBuffer()

        // Simulate processing
        try? await Task.sleep(for: .seconds(1))

        // Mock transcription result
        currentTranscription = "This is a test transcription."

        state = .completed
        onTranscriptionComplete?(currentTranscription)

        return currentTranscription
    }

    func cancelTranscription() {
        state = .idle
        currentTranscription = ""
    }

    func processAudioBuffer(_ buffer: [Float]) async throws -> String {
        guard isModelLoaded else {
            throw TranscriptionError.modelNotLoaded
        }

        state = .processing

        // Will be implemented with WhisperKit
        // let result = try await whisper.transcribe(audioArray: buffer)

        // Simulate transcription
        try await Task.sleep(for: .milliseconds(500))

        let result = "Transcribed text would appear here."
        currentTranscription = result

        state = .completed
        return result
    }

    enum TranscriptionError: LocalizedError {
        case modelNotLoaded
        case transcriptionFailed(underlying: Error?)

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "No transcription model is loaded. Please download and select a model."
            case .transcriptionFailed(let error):
                return "Transcription failed: \(error?.localizedDescription ?? "Unknown error")"
            }
        }
    }
}
