//
//  ModelDownloadService.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import Foundation
import WhisperKit
import FluidAudio

@MainActor
@Observable
final class ModelDownloadService {
    static let shared = ModelDownloadService()

    private(set) var activeDownloads: [String: DownloadTask] = [:]
    private(set) var downloadedModels: Set<String> = []

    struct DownloadTask: Sendable {
        let modelID: String
        var progress: Double
        var error: Error?
        var isCompleted: Bool
    }

    private init() {
        Task {
            await refreshDownloadedModels()
        }
    }

    // MARK: - Model Discovery

    func fetchAvailableModels() async -> [UnifiedModelInfo] {
        // Return all available models from both providers
        return UnifiedModelInfo.allModels
    }

    // MARK: - Model Download

    func downloadModel(modelID: String) async throws {
        // Allow re-download if previous attempt completed (success or failure)
        if let existingDownload = activeDownloads[modelID], !existingDownload.isCompleted {
            throw DownloadError.alreadyDownloading
        }

        // Clear any completed download entry before starting fresh
        activeDownloads.removeValue(forKey: modelID)

        guard let modelInfo = UnifiedModelInfo.model(forID: modelID) else {
            throw DownloadError.modelNotFound
        }

        print("Starting download for model: \(modelID)")

        activeDownloads[modelID] = DownloadTask(
            modelID: modelID,
            progress: 0,
            error: nil,
            isCompleted: false
        )

        do {
            switch modelInfo.provider {
            case .whisperKit:
                try await downloadWhisperModel(variant: modelInfo.variant, modelID: modelID)
            case .fluidAudio:
                try await downloadFluidAudioModel(variant: modelInfo.variant, modelID: modelID)
            }

            print("Download completed for \(modelID)")

            activeDownloads[modelID]?.progress = 1.0
            activeDownloads[modelID]?.isCompleted = true

            // Add to downloaded models
            downloadedModels.insert(modelID)

            // Remove from active downloads after a delay
            Task {
                try? await Task.sleep(for: .seconds(2))
                activeDownloads.removeValue(forKey: modelID)
            }

        } catch {
            print("Download failed for \(modelID): \(error)")
            activeDownloads[modelID]?.error = error
            activeDownloads[modelID]?.isCompleted = true

            // Remove from active downloads after showing error
            Task {
                try? await Task.sleep(for: .seconds(3))
                activeDownloads.removeValue(forKey: modelID)
            }

            throw DownloadError.downloadFailed(underlying: error)
        }
    }

    private func downloadWhisperModel(variant: String, modelID: String) async throws {
        print("Calling WhisperKit.download for \(variant) from argmaxinc/whisperkit-coreml")
        _ = try await WhisperKit.download(
            variant: variant,
            from: "argmaxinc/whisperkit-coreml",
            progressCallback: { progress in
                Task { @MainActor in
                    self.activeDownloads[modelID]?.progress = progress.fractionCompleted
                    if Int(progress.fractionCompleted * 100) % 10 == 0 {
                        print("Download progress for \(variant): \(Int(progress.fractionCompleted * 100))%")
                    }
                }
            }
        )
    }

    private func downloadFluidAudioModel(variant: String, modelID: String) async throws {
        print("Downloading FluidAudio model: \(variant)")

        // FluidAudio downloads automatically when loading
        // We'll do a "pre-download" by loading and then discarding
        let version: AsrModelVersion = variant == "v2" ? .v2 : .v3

        // Update progress manually since FluidAudio doesn't provide progress callbacks
        activeDownloads[modelID]?.progress = 0.1

        do {
            _ = try await AsrModels.downloadAndLoad(version: version)
            activeDownloads[modelID]?.progress = 1.0
            print("FluidAudio model downloaded successfully: \(variant)")
        } catch {
            print("FluidAudio download error for \(variant): \(error)")
            print("Error type: \(type(of: error))")
            if let nsError = error as NSError? {
                print("NSError domain: \(nsError.domain), code: \(nsError.code)")
                print("NSError userInfo: \(nsError.userInfo)")
            }
            throw error
        }
    }

    func cancelDownload(modelID: String) {
        activeDownloads.removeValue(forKey: modelID)
    }

    func isModelDownloaded(_ modelID: String) -> Bool {
        downloadedModels.contains(modelID)
    }

    func progress(for modelID: String) -> Double {
        activeDownloads[modelID]?.progress ?? 0
    }

    // MARK: - Model Management

    func refreshDownloadedModels() async {
        let fileManager = FileManager.default
        var foundModels: Set<String> = []

        // Check WhisperKit models in multiple possible locations
        // Location varies based on WhisperKit version and sandbox configuration
        var whisperKitSearchPaths: [URL] = []

        // Location 1: Documents/huggingface (current sandboxed location)
        if let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            whisperKitSearchPaths.append(documentsDir.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml"))
        }

        // Location 2: Caches/huggingface/hub (alternative HuggingFace cache location)
        if let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            // Standard HuggingFace hub cache structure
            let hubDir = cachesDir.appendingPathComponent("huggingface/hub/models--argmaxinc--whisperkit-coreml/snapshots")
            if let snapshots = try? fileManager.contentsOfDirectory(at: hubDir, includingPropertiesForKeys: nil) {
                whisperKitSearchPaths.append(contentsOf: snapshots)
            }
        }

        // Search all paths for WhisperKit models
        for searchPath in whisperKitSearchPaths {
            if let contents = try? fileManager.contentsOfDirectory(at: searchPath, includingPropertiesForKeys: nil) {
                for item in contents {
                    let name = item.lastPathComponent
                    // Skip hidden directories like .cache
                    guard !name.hasPrefix(".") else { continue }

                    // Check if it's a valid model directory with config.json
                    let hasConfig = fileManager.fileExists(atPath: item.appendingPathComponent("config.json").path)
                    if hasConfig {
                        let modelID = "whisperkit:\(name)"
                        foundModels.insert(modelID)
                        print("Found WhisperKit model: \(modelID) at \(item.path)")
                    }
                }
            }
        }

        // Look for FluidAudio/Parakeet CoreML models in Application Support
        // FluidAudio stores models in ~/Library/Application Support/FluidAudio/Models/
        if let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let fluidModelsDir = appSupportDir.appendingPathComponent("FluidAudio/Models")
            let fluidModelV2 = fluidModelsDir.appendingPathComponent("parakeet-tdt-0.6b-v2-coreml")
            let fluidModelV3 = fluidModelsDir.appendingPathComponent("parakeet-tdt-0.6b-v3-coreml")

            // Check v2 model - verify directory exists and contains actual model files
            if let contents = try? fileManager.contentsOfDirectory(at: fluidModelV2, includingPropertiesForKeys: nil),
               !contents.isEmpty {
                foundModels.insert("fluidaudio:v2")
                print("Found FluidAudio model: fluidaudio:v2 at \(fluidModelV2.path)")
            }

            // Check v3 model - verify directory exists and contains actual model files
            if let contents = try? fileManager.contentsOfDirectory(at: fluidModelV3, includingPropertiesForKeys: nil),
               !contents.isEmpty {
                foundModels.insert("fluidaudio:v3")
                print("Found FluidAudio model: fluidaudio:v3 at \(fluidModelV3.path)")
            }
        }

        downloadedModels = foundModels
        print("Downloaded models: \(downloadedModels)")
    }

    func deleteModel(modelID: String) async throws {
        guard let modelInfo = UnifiedModelInfo.model(forID: modelID) else {
            throw DownloadError.modelNotFound
        }

        let fileManager = FileManager.default

        switch modelInfo.provider {
        case .whisperKit:
            // WhisperKit models are in Documents/huggingface/models/argmaxinc/whisperkit-coreml/{variant}/
            if let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                let modelDir = documentsDir.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml/\(modelInfo.variant)")

                if fileManager.fileExists(atPath: modelDir.path) {
                    try fileManager.removeItem(at: modelDir)
                    print("Deleted WhisperKit model at: \(modelDir.path)")
                }
            }

        case .fluidAudio:
            // FluidAudio stores models in Application Support
            if let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let modelName = modelInfo.variant == "v2"
                    ? "parakeet-tdt-0.6b-v2-coreml"
                    : "parakeet-tdt-0.6b-v3-coreml"
                let modelDir = appSupportDir.appendingPathComponent("FluidAudio/Models/\(modelName)")

                if fileManager.fileExists(atPath: modelDir.path) {
                    try fileManager.removeItem(at: modelDir)
                    print("Deleted FluidAudio model at: \(modelDir.path)")
                }
            }
        }

        downloadedModels.remove(modelID)
        await refreshDownloadedModels()
    }

    // MARK: - Types

    enum DownloadError: LocalizedError {
        case alreadyDownloading
        case downloadFailed(underlying: Error?)
        case modelNotFound

        var errorDescription: String? {
            switch self {
            case .alreadyDownloading:
                return "This model is already being downloaded."
            case .downloadFailed(let error):
                return "Download failed: \(error?.localizedDescription ?? "Unknown error")"
            case .modelNotFound:
                return "Model not found."
            }
        }
    }
}
