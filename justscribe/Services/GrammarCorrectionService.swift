//
//  GrammarCorrectionService.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 17/02/2026.
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

@MainActor
@Observable
final class GrammarCorrectionService {
    static let shared = GrammarCorrectionService()

    private(set) var isModelLoaded = false
    private(set) var isProcessing = false
    private(set) var isLoadingModel = false
    private(set) var loadProgress: Double = 0
    private(set) var loadedModelID: String?
    private(set) var downloadedModels: Set<String> = []
    private(set) var activelyDownloadingModelID: String?

    private var modelContainer: ModelContainer?
    private var chatSession: ChatSession?

    private static let systemPrompt = """
        You are a grammar correction assistant. Fix grammar, spelling, and punctuation errors \
        in the following text. Preserve the original meaning and tone. Output ONLY the corrected \
        text with no explanations, no quotes, and no additional formatting.
        """

    private init() {
        refreshDownloadedModels()
    }

    // MARK: - Discovery

    func refreshDownloadedModels() {
        var found: Set<String> = []
        for model in GrammarCorrectionModel.allModels {
            if Self.isModelOnDisk(hubID: model.hubID) {
                found.insert(model.id)
            }
        }
        downloadedModels = found
    }

    func isModelDownloaded(_ modelID: String) -> Bool {
        downloadedModels.contains(modelID)
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

    // MARK: - Load / Download

    /// Download (if needed) and load the given grammar model into memory.
    func loadModel(modelID: String) async throws {
        guard let model = GrammarCorrectionModel.model(forID: modelID) else {
            throw GrammarCorrectionError.modelNotFound
        }

        if isModelLoaded && loadedModelID == modelID {
            return
        }

        if isLoadingModel {
            return
        }

        // If switching models, unload the previous one first.
        if isModelLoaded && loadedModelID != modelID {
            unloadModel()
        }

        isLoadingModel = true
        loadProgress = 0
        let wasOnDisk = Self.isModelOnDisk(hubID: model.hubID)
        if !wasOnDisk {
            activelyDownloadingModelID = modelID
        }

        do {
            let configuration = ModelConfiguration(id: model.hubID)
            let container = try await loadModelContainer(configuration: configuration) { [weak self] progress in
                Task { @MainActor in
                    self?.loadProgress = progress.fractionCompleted
                }
            }

            modelContainer = container
            chatSession = ChatSession(
                container,
                instructions: Self.systemPrompt,
                generateParameters: GenerateParameters(maxTokens: 2048, temperature: 0.1)
            )
            isModelLoaded = true
            loadedModelID = modelID
            isLoadingModel = false
            activelyDownloadingModelID = nil
            loadProgress = 1.0
            downloadedModels.insert(modelID)
            print("Grammar correction model loaded successfully: \(modelID)")
        } catch {
            isLoadingModel = false
            activelyDownloadingModelID = nil
            loadProgress = 0
            print("Failed to load grammar correction model \(modelID): \(error)")
            throw error
        }
    }

    /// Delete the on-disk files for a downloaded grammar model. If the model is currently
    /// loaded, it will be unloaded first.
    func deleteModel(modelID: String) throws {
        guard let model = GrammarCorrectionModel.model(forID: modelID) else {
            throw GrammarCorrectionError.modelNotFound
        }

        if loadedModelID == modelID {
            unloadModel()
        }

        let fileManager = FileManager.default
        guard let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }
        let modelDir = cachesDir.appendingPathComponent("models").appendingPathComponent(model.hubID)
        if fileManager.fileExists(atPath: modelDir.path) {
            try fileManager.removeItem(at: modelDir)
            print("Deleted grammar correction model at: \(modelDir.path)")
        }

        downloadedModels.remove(modelID)
    }

    func unloadModel() {
        chatSession = nil
        modelContainer = nil
        isModelLoaded = false
        isProcessing = false
        loadProgress = 0
        loadedModelID = nil
        print("Grammar correction model unloaded")
    }

    // MARK: - Correction

    func correctGrammar(_ text: String, language: String? = nil) async throws -> String {
        guard let session = chatSession else {
            throw GrammarCorrectionError.modelNotLoaded
        }

        isProcessing = true
        defer { isProcessing = false }

        // Clear previous conversation to avoid context buildup
        await session.clear()

        let prompt: String
        if let language, !language.isEmpty, language != "en" {
            prompt = "Language: \(language). Text: \(text)"
        } else {
            prompt = text
        }

        // Use timeout to prevent hanging
        let corrected = try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await session.respond(to: prompt)
            }

            group.addTask {
                try await Task.sleep(for: .seconds(30))
                throw GrammarCorrectionError.timeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }

        let trimmed = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        print("Grammar correction: '\(text)' -> '\(trimmed)'")
        return trimmed
    }

    enum GrammarCorrectionError: LocalizedError {
        case modelNotLoaded
        case modelNotFound
        case timeout

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "Grammar correction model is not loaded."
            case .modelNotFound:
                return "Grammar correction model not found."
            case .timeout:
                return "Grammar correction timed out."
            }
        }
    }
}
