//
//  HostedProvider.swift
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

/// A hosted language-model service the user can send clean-up to with their own API key.
/// Every provider but Anthropic speaks the OpenAI chat-completions dialect; Anthropic has its
/// own Messages API. The model name is the user's to change: these names go stale.
nonisolated enum HostedProvider: String, CaseIterable, Codable, Sendable, Identifiable {
    case groq
    case anthropic
    case openai
    case gemini
    case mistral
    case openrouter

    var id: String { rawValue }

    /// The grammar model ID this provider is selected under: "hosted:groq".
    var modelID: String { "\(Self.modelIDPrefix)\(rawValue)" }
    static let modelIDPrefix = "hosted:"

    static func provider(forModelID id: String) -> HostedProvider? {
        guard id.hasPrefix(modelIDPrefix) else { return nil }
        return HostedProvider(rawValue: String(id.dropFirst(modelIDPrefix.count)))
    }

    /// The provider last shown in Settings.
    static let selectedKey = "grammar.hosted.provider"
    /// The model name the user typed for this provider; empty means `defaultModel`.
    var modelKey: String { "grammar.hosted.model.\(rawValue)" }

    enum Wire: Equatable, Sendable {
        case openAIChat
        case anthropicMessages
    }

    var displayName: String {
        switch self {
        case .groq: "Groq"
        case .anthropic: "Anthropic (Claude)"
        case .openai: "OpenAI"
        case .gemini: "Google Gemini"
        case .mistral: "Mistral"
        case .openrouter: "OpenRouter"
        }
    }

    var wire: Wire {
        self == .anthropic ? .anthropicMessages : .openAIChat
    }

    var endpoint: URL {
        switch self {
        case .groq: URL(string: "https://api.groq.com/openai/v1/chat/completions")!
        case .anthropic: URL(string: "https://api.anthropic.com/v1/messages")!
        case .openai: URL(string: "https://api.openai.com/v1/chat/completions")!
        case .gemini: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")!
        case .mistral: URL(string: "https://api.mistral.ai/v1/chat/completions")!
        case .openrouter: URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        }
    }

    /// Where the user gets a key.
    var keyPageURL: URL {
        switch self {
        case .groq: URL(string: "https://console.groq.com/keys")!
        case .anthropic: URL(string: "https://console.anthropic.com/settings/keys")!
        case .openai: URL(string: "https://platform.openai.com/api-keys")!
        case .gemini: URL(string: "https://aistudio.google.com/apikey")!
        case .mistral: URL(string: "https://console.mistral.ai/api-keys")!
        case .openrouter: URL(string: "https://openrouter.ai/keys")!
        }
    }

    var defaultModel: String {
        switch self {
        case .groq: "llama-3.3-70b-versatile"
        case .anthropic: "claude-opus-5"
        case .openai: "gpt-5-mini"
        case .gemini: "gemini-2.5-flash"
        case .mistral: "mistral-small-latest"
        case .openrouter: "meta-llama/llama-3.3-70b-instruct"
        }
    }

    var grammarModel: GrammarCorrectionModel {
        GrammarCorrectionModel(
            id: modelID, displayName: displayName, provider: "Hosted · your API key", backend: .hosted(self),
            hubID: nil, approximateSize: nil, approximateRAM: nil, approximateRAMInMB: nil)
    }
}

nonisolated enum HostedGrammarError: LocalizedError, Equatable {
    case noKey(HostedProvider)
    case badResponse
    case emptyResponse
    case http(status: Int, detail: String?)

    var errorDescription: String? {
        switch self {
        case .noKey(let provider): "Add your \(provider.displayName) API key in Settings."
        case .badResponse: "The provider sent a reply JustScribe couldn't read."
        case .emptyResponse: "The provider sent no text back."
        case .http(let status, let detail):
            switch status {
            case 401, 403: "The provider rejected the API key."
            case 404: "The provider doesn't know that model."
            case 429: "The provider is rate-limiting requests."
            default: "The provider answered \(status)" + (detail.map { ": \($0)" } ?? ".")
            }
        }
    }
}

/// The HTTP request to a provider and the text in its reply: pure, so both are tested without
/// a network.
nonisolated enum HostedRequest {
    static let anthropicVersion = "2023-06-01"
    /// Room for a cleaned-up dictation; the input is what bounds the output.
    static let maxOutputTokens = 4096

    static func make(
        provider: HostedProvider, model: String, apiKey: String, system: String, text: String, timeout: TimeInterval
    ) throws -> URLRequest {
        var request = URLRequest(url: provider.endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any]
        switch provider.wire {
        case .openAIChat:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            body = [
                "model": model,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": text],
                ],
            ]
        case .anthropicMessages:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
            body = [
                "model": model,
                "max_tokens": maxOutputTokens,
                "system": system,
                "messages": [["role": "user", "content": text]],
            ]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// The reply's text: the first choice's message for the chat dialect, every text block
    /// joined for Anthropic.
    static func text(from data: Data, provider: HostedProvider) throws -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HostedGrammarError.badResponse
        }
        let text: String?
        switch provider.wire {
        case .openAIChat:
            let choices = object["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]
            text = message?["content"] as? String
        case .anthropicMessages:
            let blocks = object["content"] as? [[String: Any]]
            text = blocks?.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
        }
        guard let text else { throw HostedGrammarError.badResponse }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw HostedGrammarError.emptyResponse }
        return text
    }

    /// The message in an error reply, if the provider gave one (both dialects use `error.message`).
    static func errorDetail(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let message = error["message"] as? String, !message.isEmpty else { return nil }
        return message
    }

    /// The system prompt: the mode's instructions in the usual frame, plus the language when
    /// it is not English, so the model keeps the text in it.
    static func system(instructions: String, language: String?) -> String {
        var system = GrammarPrompt.frame(instructions)
        if let language, !language.isEmpty, language != "en" {
            system += "\n\nThe text is in the language with code \"\(language)\". Keep it in that language."
        }
        return system
    }
}
