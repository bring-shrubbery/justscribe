//
//  ModelDownloadService.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import Foundation
import WhisperKit

@MainActor
@Observable
final class ModelDownloadService {
    static let shared = ModelDownloadService()

    private(set) var activeDownloads: [String: DownloadTask] = [:]
    private(set) var downloadedModels: [String] = []

    struct DownloadTask: Sendable {
        let modelVariant: String
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

    func fetchAvailableModels() async -> [WhisperModelInfo] {
        let recommended = WhisperKit.recommendedModels()

        // Convert to our model info format
        return recommended.supported.map { variant in
            WhisperModelInfo(
                variant: variant,
                displayName: displayName(for: variant),
                sizeDescription: sizeDescription(for: variant),
                isRecommended: recommended.default == variant
            )
        }
    }

    // MARK: - Model Download

    func downloadModel(variant: String) async throws -> URL {
        guard activeDownloads[variant] == nil else {
            throw DownloadError.alreadyDownloading
        }

        activeDownloads[variant] = DownloadTask(
            modelVariant: variant,
            progress: 0,
            error: nil,
            isCompleted: false
        )

        do {
            // Use WhisperKit's built-in download mechanism
            let modelPath = try await WhisperKit.download(
                variant: variant,
                progressCallback: { progress in
                    Task { @MainActor in
                        self.activeDownloads[variant]?.progress = progress.fractionCompleted
                    }
                }
            )

            activeDownloads[variant]?.progress = 1.0
            activeDownloads[variant]?.isCompleted = true

            await refreshDownloadedModels()

            return modelPath
        } catch {
            activeDownloads[variant]?.error = error
            activeDownloads[variant]?.isCompleted = true
            throw DownloadError.downloadFailed(underlying: error)
        }
    }

    func cancelDownload(variant: String) {
        activeDownloads.removeValue(forKey: variant)
    }

    func isModelDownloaded(_ variant: String) -> Bool {
        downloadedModels.contains(variant)
    }

    func progress(for variant: String) -> Double {
        activeDownloads[variant]?.progress ?? 0
    }

    // MARK: - Model Management

    func refreshDownloadedModels() async {
        do {
            let localModels = try await WhisperKit.fetchAvailableModels()
            downloadedModels = localModels
        } catch {
            downloadedModels = []
        }
    }

    func deleteModel(variant: String) async throws {
        let modelsDir = TranscriptionService.modelDirectory()
        let modelPath = modelsDir.appendingPathComponent(variant)

        if FileManager.default.fileExists(atPath: modelPath.path) {
            try FileManager.default.removeItem(at: modelPath)
        }

        await refreshDownloadedModels()
    }

    // MARK: - Helpers

    private func displayName(for variant: String) -> String {
        // Convert variant like "openai_whisper-base" to "Base"
        let name = variant
            .replacingOccurrences(of: "openai_whisper-", with: "")
            .replacingOccurrences(of: "whisper-", with: "")
            .replacingOccurrences(of: "-en", with: " (English)")
            .capitalized

        return name
    }

    private func sizeDescription(for variant: String) -> String {
        if variant.contains("tiny") { return "~75 MB" }
        if variant.contains("base") { return "~142 MB" }
        if variant.contains("small") { return "~466 MB" }
        if variant.contains("medium") { return "~1.5 GB" }
        if variant.contains("large") { return "~3 GB" }
        return "Unknown size"
    }

    private func defaultModels() -> [WhisperModelInfo] {
        [
            WhisperModelInfo(variant: "openai_whisper-tiny", displayName: "Tiny", sizeDescription: "~75 MB", isRecommended: false),
            WhisperModelInfo(variant: "openai_whisper-base", displayName: "Base", sizeDescription: "~142 MB", isRecommended: true),
            WhisperModelInfo(variant: "openai_whisper-small", displayName: "Small", sizeDescription: "~466 MB", isRecommended: false),
            WhisperModelInfo(variant: "openai_whisper-medium", displayName: "Medium", sizeDescription: "~1.5 GB", isRecommended: false),
            WhisperModelInfo(variant: "openai_whisper-large-v3", displayName: "Large v3", sizeDescription: "~3 GB", isRecommended: false),
        ]
    }

    // MARK: - Types

    struct WhisperModelInfo: Identifiable, Sendable {
        var id: String { variant }
        let variant: String
        let displayName: String
        let sizeDescription: String
        let isRecommended: Bool
    }

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
