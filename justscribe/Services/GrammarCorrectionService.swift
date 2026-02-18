//
//  GrammarCorrectionService.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 17/02/2026.
//

import Foundation
import MLXLLM
import MLXLMCommon

@Observable
final class GrammarCorrectionService {
    static let shared = GrammarCorrectionService()

    private(set) var isModelLoaded = false
    private(set) var isProcessing = false
    private(set) var isLoadingModel = false
    private(set) var loadProgress: Double = 0

    private var modelContainer: ModelContainer?
    private var chatSession: ChatSession?

    static let modelHubID = "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit"

    private static let systemPrompt = """
        You are a grammar correction assistant. Fix grammar, spelling, and punctuation errors \
        in the following text. Preserve the original meaning and tone. Output ONLY the corrected \
        text with no explanations, no quotes, and no additional formatting.
        """

    private init() {}

    func loadModel() async throws {
        guard !isModelLoaded && !isLoadingModel else { return }

        isLoadingModel = true
        loadProgress = 0

        do {
            let configuration = ModelConfiguration(id: Self.modelHubID)
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
            isLoadingModel = false
            loadProgress = 1.0
            print("Grammar correction model loaded successfully")
        } catch {
            isLoadingModel = false
            loadProgress = 0
            print("Failed to load grammar correction model: \(error)")
            throw error
        }
    }

    func unloadModel() {
        chatSession = nil
        modelContainer = nil
        isModelLoaded = false
        isProcessing = false
        loadProgress = 0
        print("Grammar correction model unloaded")
    }

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
        case timeout

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "Grammar correction model is not loaded."
            case .timeout:
                return "Grammar correction timed out."
            }
        }
    }
}
