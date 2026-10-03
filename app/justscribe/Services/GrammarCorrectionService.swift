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

/// Routes grammar correction to whichever backend serves the selected model.
/// Owns the observable state the settings UI binds to; the backends own the
/// engine-specific details.
@MainActor
@Observable
final class GrammarCorrectionService {
    static let shared = GrammarCorrectionService()

    private(set) var isModelLoaded = false
    private(set) var isProcessing = false
    private(set) var isLoadingModel = false
    private(set) var loadProgress: Double = 0
    private(set) var loadedModelID: String?
    /// MLX models present on disk. Always empty of Apple models — they aren't downloaded.
    private(set) var downloadedModels: Set<String> = []
    private(set) var activelyDownloadingModelID: String?

    private let appleBackend = AppleFoundationGrammarBackend()
    private let mlxBackend = MLXGrammarBackend()
    private var activeBackend: (any GrammarBackend)?

    private init() {
        refreshDownloadedModels()
    }

    // MARK: - Discovery

    private func backend(for modelID: String) -> (any GrammarBackend)? {
        guard let model = GrammarCorrectionModel.model(forID: modelID) else { return nil }
        switch model.backend {
        case .apple: return appleBackend
        case .mlx: return mlxBackend
        }
    }

    func refreshDownloadedModels() {
        mlxBackend.refreshDownloadedModels()
        downloadedModels = mlxBackend.downloadedModelIDs
    }

    /// Whether the model can be used right now with no further download. For MLX
    /// models that means the weights are on disk; for the Apple model it means
    /// Apple Intelligence is enabled and ready.
    func isReadyToUse(_ modelID: String) -> Bool {
        backend(for: modelID)?.availability == .available
    }

    func availability(for modelID: String) -> GrammarBackendAvailability {
        backend(for: modelID)?.availability
            ?? .unavailable(reason: "Unknown model.", settingsURL: nil)
    }

    // MARK: - Load

    func loadModel(modelID: String) async throws {
        guard let target = backend(for: modelID) else {
            throw GrammarBackendError.modelNotFound
        }

        if isModelLoaded && loadedModelID == modelID { return }
        if isLoadingModel { return }

        // If switching models, unload the previous one first.
        if isModelLoaded && loadedModelID != modelID {
            unloadModel()
        }

        isLoadingModel = true
        loadProgress = 0
        if target.availability == .requiresDownload {
            activelyDownloadingModelID = modelID
        }

        do {
            try await target.prepare { [weak self] fraction in
                self?.loadProgress = fraction
            }
            activeBackend = target
            isModelLoaded = true
            loadedModelID = modelID
            isLoadingModel = false
            activelyDownloadingModelID = nil
            loadProgress = 1.0
            refreshDownloadedModels()
            print("Grammar correction model loaded successfully: \(modelID)")
        } catch {
            isLoadingModel = false
            activelyDownloadingModelID = nil
            loadProgress = 0
            print("Failed to load grammar correction model \(modelID): \(error)")
            throw error
        }
    }

    /// Delete a downloaded model's files. Throws for models that are part of macOS.
    func deleteModel(modelID: String) throws {
        guard let target = backend(for: modelID) else {
            throw GrammarBackendError.modelNotFound
        }
        guard let mlx = target as? MLXGrammarBackend else {
            throw GrammarBackendError.notDeletable
        }
        if loadedModelID == modelID {
            unloadModel()
        }
        try mlx.delete(modelID: modelID)
        refreshDownloadedModels()
    }

    func unloadModel() {
        activeBackend?.unload()
        activeBackend = nil
        isModelLoaded = false
        isProcessing = false
        loadProgress = 0
        loadedModelID = nil
        print("Grammar correction model unloaded")
    }

    // MARK: - Correction

    func correctGrammar(_ text: String, instructions: String, language: String? = nil) async throws -> String {
        guard let backend = activeBackend else { throw GrammarBackendError.notReady }
        isProcessing = true
        defer { isProcessing = false }
        let corrected = try await backend.correct(text, instructions: instructions, language: language)
        print("Clean-up: '\(text)' -> '\(corrected)'")
        return corrected
    }
}
