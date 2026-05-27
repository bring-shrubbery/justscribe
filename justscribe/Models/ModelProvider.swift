//
//  ModelProvider.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 25/01/2026.
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
    let approximateRAMInMB: Int
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
            approximateRAMInMB: 600,
            isRecommended: true,
            languageSupport: .multilingual
        ),
        UnifiedModelInfo(
            provider: .fluidAudio,
            variant: "v2",
            displayName: "Parakeet English",
            sizeDescription: "~200 MB",
            approximateRAMInMB: 500,
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
            approximateRAMInMB: 200,
            isRecommended: false,
            languageSupport: .multilingual
        ),
        UnifiedModelInfo(
            provider: .whisperKit,
            variant: "openai_whisper-base",
            displayName: "Whisper Base",
            sizeDescription: "~142 MB",
            approximateRAMInMB: 350,
            isRecommended: false,
            languageSupport: .multilingual
        ),
        UnifiedModelInfo(
            provider: .whisperKit,
            variant: "openai_whisper-small",
            displayName: "Whisper Small",
            sizeDescription: "~466 MB",
            approximateRAMInMB: 900,
            isRecommended: false,
            languageSupport: .multilingual
        ),
        UnifiedModelInfo(
            provider: .whisperKit,
            variant: "openai_whisper-medium",
            displayName: "Whisper Medium",
            sizeDescription: "~1.5 GB",
            approximateRAMInMB: 2600,
            isRecommended: false,
            languageSupport: .multilingual
        ),
        UnifiedModelInfo(
            provider: .whisperKit,
            variant: "openai_whisper-large-v3",
            displayName: "Whisper Large v3",
            sizeDescription: "~3 GB",
            approximateRAMInMB: 5200,
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
