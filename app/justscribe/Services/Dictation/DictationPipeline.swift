//
//  DictationPipeline.swift
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

/// Everything a dictation needs to be turned into the text that is inserted.
nonisolated struct DictationContext: Sendable {
    var voiceCommands: Bool
    var spokenPunctuation: Bool
    /// Session commands ("stop recording", "send") act only in press-to-toggle mode.
    var pressToToggle: Bool
    var vocabulary: [VocabularyEntry]
    var mode: DictationMode
    /// The global Clean-up switch.
    var cleanUpEnabled: Bool
    var language: String?
}

nonisolated struct DictationResult: Equatable, Sendable {
    var text: String
    var actions: [DictationAction]
}

/// Raw transcript → voice commands → vocabulary → clean-up with the mode's instructions.
/// Pure except for clean-up and the dictionary check, which are injected.
final class DictationPipeline {
    typealias CleanUp = (_ text: String, _ instructions: String, _ language: String?) async throws -> String

    private let cleanUp: CleanUp
    private let isDictionaryWord: (String) -> Bool

    init(cleanUp: @escaping CleanUp, isDictionaryWord: @escaping (String) -> Bool) {
        self.cleanUp = cleanUp
        self.isDictionaryWord = isDictionaryWord
    }

    func process(_ raw: String, context: DictationContext) async -> DictationResult {
        let commanded = VoiceCommandProcessor.apply(
            raw, commandsOn: context.voiceCommands, punctuationOn: context.spokenPunctuation,
            sessionCommandsOn: context.pressToToggle)
        var text = VocabularyMatcher.apply(commanded.text, entries: context.vocabulary, isDictionaryWord: isDictionaryWord)

        if context.cleanUpEnabled, context.mode.cleanUp, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Clean-up backends trim their output; a line break spoken at the end must survive.
            let trailing = String(text.reversed().prefix(while: { $0 == "\n" }))
            do {
                var cleaned = try await cleanUp(text, context.mode.effectiveInstructions, context.language)
                if !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if !trailing.isEmpty && !cleaned.hasSuffix("\n") { cleaned += trailing }
                    text = cleaned
                }
            } catch {
                print("Clean-up failed, keeping the text as dictated: \(error)")
            }
        }
        return DictationResult(text: text, actions: commanded.actions)
    }

    /// The session command the streamed text ends with — checked live while recording.
    nonisolated static func terminatingCommand(in streamed: String, context: DictationContext) -> DictationAction? {
        guard context.voiceCommands else { return nil }
        return VoiceCommandProcessor.terminatingCommand(in: streamed, sessionCommandsOn: context.pressToToggle)
    }
}
