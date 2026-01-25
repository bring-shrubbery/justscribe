//
//  TranscriptionService.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import Foundation
import WhisperKit
import FluidAudio

@MainActor
@Observable
final class TranscriptionService {
    static let shared = TranscriptionService()

    private(set) var state: TranscriptionState = .idle
    private(set) var currentTranscription: String = ""
    private(set) var isModelLoaded = false
    private(set) var loadedModelID: String?
    private(set) var loadedProvider: ModelProvider?

    // WhisperKit
    private var whisperKit: WhisperKit?

    // FluidAudio
    private var asrManager: AsrManager?
    private var asrModels: AsrModels?

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

    /// Load a model using the unified model ID format (provider:variant)
    func loadModel(unifiedID: String) async throws {
        guard let modelInfo = UnifiedModelInfo.model(forID: unifiedID) else {
            throw TranscriptionError.modelNotFound
        }

        switch modelInfo.provider {
        case .whisperKit:
            try await loadWhisperModel(variant: modelInfo.variant)
        case .fluidAudio:
            try await loadFluidAudioModel(variant: modelInfo.variant)
        }

        loadedModelID = unifiedID
        loadedProvider = modelInfo.provider
    }

    /// Load a WhisperKit model
    func loadWhisperModel(variant: String) async throws {
        state = .loadingModel
        unloadModel()

        do {
            print("Loading WhisperKit model: \(variant)")
            let config = WhisperKitConfig(
                model: variant,
                modelRepo: "argmaxinc/whisperkit-coreml",
                verbose: true,
                logLevel: .debug
            )
            whisperKit = try await WhisperKit(config)
            loadedModelID = "whisperkit:\(variant)"
            loadedProvider = .whisperKit
            isModelLoaded = true
            state = .idle
            print("WhisperKit model loaded successfully")
        } catch {
            state = .error("Failed to load model: \(error.localizedDescription)")
            print("WhisperKit load error: \(error)")
            throw TranscriptionError.modelLoadFailed(underlying: error)
        }
    }

    /// Load a FluidAudio/Parakeet model
    func loadFluidAudioModel(variant: String) async throws {
        state = .loadingModel
        unloadModel()

        do {
            print("Loading FluidAudio model: \(variant)")

            // Determine version from variant
            let version: AsrModelVersion = variant == "v2" ? .v2 : .v3

            // Download and load the model
            asrModels = try await AsrModels.downloadAndLoad(version: version)
            asrManager = AsrManager(config: .default)
            try await asrManager?.initialize(models: asrModels!)

            loadedModelID = "fluidaudio:\(variant)"
            loadedProvider = .fluidAudio
            isModelLoaded = true
            state = .idle
            print("FluidAudio model loaded successfully")
        } catch {
            state = .error("Failed to load model: \(error.localizedDescription)")
            print("FluidAudio load error: \(error)")
            throw TranscriptionError.modelLoadFailed(underlying: error)
        }
    }

    func unloadModel() {
        whisperKit = nil
        asrManager = nil
        asrModels = nil
        isModelLoaded = false
        loadedModelID = nil
        loadedProvider = nil
        state = .idle
    }

    // Legacy method for backwards compatibility
    func loadModel(variant: String) async throws {
        // Detect provider from variant name
        if variant.starts(with: "openai_whisper") || variant.starts(with: "whisper") {
            try await loadWhisperModel(variant: variant)
        } else if variant == "v2" || variant == "v3" {
            try await loadFluidAudioModel(variant: variant)
        } else {
            // Try to parse as unified ID
            try await loadModel(unifiedID: variant)
        }
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
        guard isModelLoaded else {
            throw TranscriptionError.modelNotLoaded
        }

        state = .processing

        do {
            let transcription: String

            switch loadedProvider {
            case .whisperKit:
                transcription = try await transcribeWithWhisperKit(buffer: buffer, language: language)
            case .fluidAudio:
                transcription = try await transcribeWithFluidAudio(buffer: buffer)
            case nil:
                throw TranscriptionError.modelNotLoaded
            }

            currentTranscription = transcription
            state = .completed

            return transcription
        } catch {
            state = .error("Transcription failed: \(error.localizedDescription)")
            throw TranscriptionError.transcriptionFailed(underlying: error)
        }
    }

    private func transcribeWithWhisperKit(buffer: [Float], language: String?) async throws -> String {
        guard let whisperKit = whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        var options = DecodingOptions()
        if let language = language, !language.isEmpty {
            options.language = language
        }

        let results = try await whisperKit.transcribe(audioArray: buffer, decodeOptions: options)
        return results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func transcribeWithFluidAudio(buffer: [Float]) async throws -> String {
        guard let asrManager = asrManager else {
            throw TranscriptionError.modelNotLoaded
        }

        let result = try await asrManager.transcribe(buffer)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
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
        case modelNotFound
        case modelLoadFailed(underlying: Error)
        case transcriptionFailed(underlying: Error?)

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "No transcription model is loaded. Please download and select a model."
            case .modelNotFound:
                return "Model not found. Please check the model ID."
            case .modelLoadFailed(let error):
                return "Failed to load model: \(error.localizedDescription)"
            case .transcriptionFailed(let error):
                return "Transcription failed: \(error?.localizedDescription ?? "Unknown error")"
            }
        }
    }
}
