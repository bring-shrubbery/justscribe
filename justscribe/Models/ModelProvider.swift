//
//  ModelProvider.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 25/01/2026.
//

import Foundation

/// Represents different speech-to-text model providers
enum ModelProvider: String, Codable, CaseIterable {
    case whisperKit = "whisperkit"
    case fluidAudio = "fluidaudio"

    var displayName: String {
        switch self {
        case .whisperKit:
            return "WhisperKit"
        case .fluidAudio:
            return "Parakeet"
        }
    }
}

/// Unified model information that works across providers
struct UnifiedModelInfo: Identifiable, Sendable {
    var id: String { "\(provider.rawValue):\(variant)" }

    let provider: ModelProvider
    let variant: String
    let displayName: String
    let sizeDescription: String
    let isRecommended: Bool
    let languageSupport: LanguageSupport

    enum LanguageSupport: Sendable {
        case englishOnly
        case multilingual
    }

    var fullDisplayName: String {
        "\(displayName) (\(provider.displayName))"
    }
}

/// Extension to provide all available models
extension UnifiedModelInfo {
    /// All available Parakeet models from FluidAudio
    static let parakeetModels: [UnifiedModelInfo] = [
        UnifiedModelInfo(
            provider: .fluidAudio,
            variant: "v3",
            displayName: "Parakeet v3",
            sizeDescription: "~250 MB",
            isRecommended: true,
            languageSupport: .multilingual
        ),
        UnifiedModelInfo(
            provider: .fluidAudio,
            variant: "v2",
            displayName: "Parakeet English",
            sizeDescription: "~200 MB",
            isRecommended: false,
            languageSupport: .englishOnly
        ),
    ]

    /// All available WhisperKit models
    static let whisperModels: [UnifiedModelInfo] = [
        UnifiedModelInfo(
            provider: .whisperKit,
            variant: "openai_whisper-tiny",
            displayName: "Whisper Tiny",
            sizeDescription: "~75 MB",
            isRecommended: false,
            languageSupport: .multilingual
        ),
        UnifiedModelInfo(
            provider: .whisperKit,
            variant: "openai_whisper-base",
            displayName: "Whisper Base",
            sizeDescription: "~142 MB",
            isRecommended: false,
            languageSupport: .multilingual
        ),
        UnifiedModelInfo(
            provider: .whisperKit,
            variant: "openai_whisper-small",
            displayName: "Whisper Small",
            sizeDescription: "~466 MB",
            isRecommended: false,
            languageSupport: .multilingual
        ),
        UnifiedModelInfo(
            provider: .whisperKit,
            variant: "openai_whisper-medium",
            displayName: "Whisper Medium",
            sizeDescription: "~1.5 GB",
            isRecommended: false,
            languageSupport: .multilingual
        ),
        UnifiedModelInfo(
            provider: .whisperKit,
            variant: "openai_whisper-large-v3",
            displayName: "Whisper Large v3",
            sizeDescription: "~3 GB",
            isRecommended: false,
            languageSupport: .multilingual
        ),
    ]

    /// All available models from all providers
    static var allModels: [UnifiedModelInfo] {
        parakeetModels + whisperModels
    }

    /// Get a model by its full ID (provider:variant)
    static func model(forID id: String) -> UnifiedModelInfo? {
        allModels.first { $0.id == id }
    }
}
