//
//  MLXGrammarBackend.swift
//  justscribe
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
import MLXLLM
import MLXLMCommon

/// Grammar correction via an MLX model downloaded from Hugging Face and held in
/// our own process. Serves `GrammarCorrectionModel.llama3_1_8b_4bit`.
@MainActor
final class MLXGrammarBackend: GrammarBackend {

    let modelID = GrammarCorrectionModel.llama3_1_8b_4bit.id

    private static let systemPrompt = """
        You are a grammar correction assistant. Fix grammar, spelling, and punctuation errors \
        in the following text. Preserve the original meaning and tone. Output ONLY the corrected \
        text with no explanations, no quotes, and no additional formatting.
        """

    private static let requestTimeout: Duration = .seconds(30)

    private(set) var isReady = false
    private(set) var downloadedModelIDs: Set<String> = []

    private var modelContainer: ModelContainer?
    private var chatSession: ChatSession?

    init() {
        refreshDownloadedModels()
    }

    var availability: GrammarBackendAvailability {
        guard let model = GrammarCorrectionModel.model(forID: modelID), let hubID = model.hubID else {
            return .unavailable(reason: "Unknown model.", settingsURL: nil)
        }
        return Self.isModelOnDisk(hubID: hubID) ? .available : .requiresDownload
    }

    // MARK: - Discovery

    func refreshDownloadedModels() {
        var found: Set<String> = []
        for model in GrammarCorrectionModel.allModels where model.backend == .mlx {
            if let hubID = model.hubID, Self.isModelOnDisk(hubID: hubID) {
                found.insert(model.id)
            }
        }
        downloadedModelIDs = found
    }

    /// Probe the on-disk MLX/HuggingFace cache for the given hub ID.
    /// MLX-LM stores model files under `Library/Caches/models/<org>/<repo>/`.
    private static func isModelOnDisk(hubID: String) -> Bool {
        let fileManager = FileManager.default
        guard let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return false
        }
        let modelDir = cachesDir.appendingPathComponent("models").appendingPathComponent(hubID)
        let config = modelDir.appendingPathComponent("config.json")
        let weights = modelDir.appendingPathComponent("model.safetensors")
        let weightsIndex = modelDir.appendingPathComponent("model.safetensors.index.json")
        return fileManager.fileExists(atPath: config.path)
            && (fileManager.fileExists(atPath: weights.path) || fileManager.fileExists(atPath: weightsIndex.path))
    }

    // MARK: - Lifecycle

    func prepare(onProgress: @escaping @MainActor (Double) -> Void) async throws {
        guard let model = GrammarCorrectionModel.model(forID: modelID), let hubID = model.hubID else {
            throw GrammarBackendError.modelNotFound
        }

        let configuration = ModelConfiguration(id: hubID)
        let container = try await loadModelContainer(configuration: configuration) { progress in
            Task { @MainActor in
                onProgress(progress.fractionCompleted)
            }
        }

        modelContainer = container
        chatSession = ChatSession(
            container,
            instructions: Self.systemPrompt,
            generateParameters: GenerateParameters(maxTokens: 2048, temperature: 0.1)
        )
        isReady = true
        refreshDownloadedModels()
    }

    /// Delete the on-disk files for a downloaded model. Unloads first if it is active.
    func delete(modelID: String) throws {
        guard let model = GrammarCorrectionModel.model(forID: modelID), let hubID = model.hubID else {
            throw GrammarBackendError.modelNotFound
        }

        if self.modelID == modelID && isReady {
            unload()
        }

        let fileManager = FileManager.default
        guard let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }
        let modelDir = cachesDir.appendingPathComponent("models").appendingPathComponent(hubID)
        if fileManager.fileExists(atPath: modelDir.path) {
            try fileManager.removeItem(at: modelDir)
            print("Deleted grammar correction model at: \(modelDir.path)")
        }

        refreshDownloadedModels()
    }

    func unload() {
        chatSession = nil
        modelContainer = nil
        isReady = false
    }

    // MARK: - Correction

    func correct(_ text: String, language: String?) async throws -> String {
        guard let session = chatSession else {
            throw GrammarBackendError.notReady
        }

        // Clear previous conversation to avoid context buildup
        await session.clear()

        let prompt: String
        if let language, !language.isEmpty, language != "en" {
            prompt = "Language: \(language). Text: \(text)"
        } else {
            prompt = text
        }

        let corrected = try await withGrammarTimeout(Self.requestTimeout) {
            try await session.respond(to: prompt)
        }
        return corrected.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
