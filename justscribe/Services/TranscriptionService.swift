//
//  TranscriptionService.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import Foundation
import WhisperKit

@MainActor
@Observable
final class TranscriptionService {
    static let shared = TranscriptionService()

    private(set) var state: TranscriptionState = .idle
    private(set) var currentTranscription: String = ""
    private(set) var isModelLoaded = false
    private(set) var loadedModelID: String?

    private var whisperKit: WhisperKit?

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

        do {
            whisperKit = try await WhisperKit(modelFolder: path.path)
            loadedModelID = id
            isModelLoaded = true
            state = .idle
        } catch {
            state = .error("Failed to load model: \(error.localizedDescription)")
            throw TranscriptionError.modelLoadFailed(underlying: error)
        }
    }

    func loadModel(variant: String) async throws {
        state = .loadingModel

        do {
            // WhisperKit can download and load models automatically
            whisperKit = try await WhisperKit(model: variant)
            loadedModelID = variant
            isModelLoaded = true
            state = .idle
        } catch {
            state = .error("Failed to load model: \(error.localizedDescription)")
            throw TranscriptionError.modelLoadFailed(underlying: error)
        }
    }

    func unloadModel() {
        whisperKit = nil
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

        let audioBuffer = AudioCaptureService.shared.getAudioBuffer()

        do {
            currentTranscription = try await processAudioBuffer(audioBuffer)
        } catch {
            state = .error(error.localizedDescription)
            return ""
        }

        state = .completed
        onTranscriptionComplete?(currentTranscription)

        return currentTranscription
    }

    func cancelTranscription() {
        state = .idle
        currentTranscription = ""
    }

    func processAudioBuffer(_ buffer: [Float], language: String? = nil) async throws -> String {
        guard let whisperKit = whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        state = .processing

        do {
            // Configure decoding options with language if specified
            var options = DecodingOptions()
            if let language = language, !language.isEmpty {
                options.language = language
            }

            let results = try await whisperKit.transcribe(audioArray: buffer, decodeOptions: options)
            let transcription = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

            currentTranscription = transcription
            state = .completed

            return transcription
        } catch {
            state = .error("Transcription failed: \(error.localizedDescription)")
            throw TranscriptionError.transcriptionFailed(underlying: error)
        }
    }

    // MARK: - Model Info

    static func availableModels() -> [String] {
        WhisperKit.recommendedModels().supported
    }

    static func modelDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsDir = appSupport.appendingPathComponent("JustScribe/Models", isDirectory: true)

        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        return modelsDir
    }

    enum TranscriptionError: LocalizedError {
        case modelNotLoaded
        case modelLoadFailed(underlying: Error)
        case transcriptionFailed(underlying: Error?)

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "No transcription model is loaded. Please download and select a model."
            case .modelLoadFailed(let error):
                return "Failed to load model: \(error.localizedDescription)"
            case .transcriptionFailed(let error):
                return "Transcription failed: \(error?.localizedDescription ?? "Unknown error")"
            }
        }
    }
}
