//
//  AppleFoundationGrammarBackend.swift
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
import FoundationModels

/// Grammar correction via Apple's on-device foundation model. Part of macOS:
/// nothing to download, and the OS owns the memory.
@MainActor
final class AppleFoundationGrammarBackend: GrammarBackend {

    let modelID = GrammarCorrectionModel.appleFoundation.id

    /// Text at or below this length goes through in a single request. The model's
    /// context window is ~4096 tokens shared between prompt and response.
    private static let singleShotLimit = 4000
    private static let chunkLength = 2000
    private static let requestTimeout: Duration = .seconds(20)

    private static let instructions = """
        You are a grammar correction assistant. Fix grammar, spelling, and punctuation errors \
        in the following text. Preserve the original meaning and tone. Output ONLY the corrected \
        text with no explanations, no quotes, and no additional formatting.
        """

    /// Apple Intelligence & Siri pane.
    nonisolated static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.Siri-Settings.extension"
    )

    private(set) var isReady = false

    var availability: GrammarBackendAvailability {
        Self.availability(for: SystemLanguageModel.default.availability)
    }

    /// Pure mapping, split out so it can be tested without eligible hardware.
    nonisolated static func availability(
        for modelAvailability: SystemLanguageModel.Availability
    ) -> GrammarBackendAvailability {
        switch modelAvailability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable(
                reason: "Apple Intelligence isn't supported on this Mac.",
                settingsURL: nil
            )
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(
                reason: "Turn on Apple Intelligence in System Settings.",
                settingsURL: settingsURL
            )
        case .unavailable(.modelNotReady):
            return .unavailable(
                reason: "macOS is still downloading the model. Try again shortly.",
                settingsURL: settingsURL
            )
        @unknown default:
            return .unavailable(
                reason: "Apple Intelligence isn't available right now.",
                settingsURL: nil
            )
        }
    }

    // MARK: - Lifecycle

    func prepare(onProgress: @escaping @MainActor (Double) -> Void) async throws {
        guard case .available = availability else {
            throw GrammarBackendError.unavailable(
                availability.unavailableReason ?? "Apple Intelligence isn't available."
            )
        }
        // Nothing to download; just warm the model so the first correction isn't slow.
        makeSession().prewarm()
        isReady = true
        onProgress(1.0)
    }

    func unload() {
        isReady = false
    }

    // MARK: - Correction

    func correct(_ text: String, language: String?) async throws -> String {
        guard isReady else { throw GrammarBackendError.notReady }

        if text.count <= Self.singleShotLimit {
            return try await correctOne(text, language: language)
        }

        var corrected: [String] = []
        for chunk in GrammarTextChunker.chunks(text, maxLength: Self.chunkLength) {
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                corrected.append(chunk)
                continue
            }
            do {
                let result = try await correctOne(trimmed, language: language)
                corrected.append(Self.reapplyPadding(from: chunk, to: result))
            } catch {
                // A refusal or timeout on one chunk shouldn't discard the corrections
                // around it — keep this chunk's original text and carry on.
                print("Grammar correction chunk failed, keeping original: \(error)")
                corrected.append(chunk)
            }
        }
        return corrected.joined()
    }

    // MARK: - Private

    private func makeSession() -> LanguageModelSession {
        LanguageModelSession(instructions: Self.instructions)
    }

    private func correctOne(_ text: String, language: String?) async throws -> String {
        let prompt: String
        if let language, !language.isEmpty, language != "en" {
            prompt = "Language: \(language). Text: \(text)"
        } else {
            prompt = text
        }

        // A fresh session per request keeps context from accumulating across dictations.
        // Extract `.content` inside the closure: `Response` is not Sendable, `String` is.
        let session = makeSession()
        let corrected = try await withGrammarTimeout(Self.requestTimeout) {
            try await session.respond(
                to: prompt,
                options: GenerationOptions(sampling: .greedy)
            ).content
        }
        return corrected.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Restore the whitespace trimmed off a chunk before generation, so rejoining
    /// the corrected chunks reproduces the original spacing.
    nonisolated static func reapplyPadding(from original: String, to corrected: String) -> String {
        let leading = original.prefix { $0.isWhitespace }
        let trailing = String(original.reversed().prefix { $0.isWhitespace }.reversed())
        return String(leading) + corrected + trailing
    }
}

private extension GrammarBackendAvailability {
    var unavailableReason: String? {
        if case .unavailable(let reason, _) = self { return reason }
        return nil
    }
}
