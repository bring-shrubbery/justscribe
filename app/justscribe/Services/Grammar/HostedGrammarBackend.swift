//
//  HostedGrammarBackend.swift
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

/// Clean-up through a hosted provider with the user's own API key: one instance per provider.
/// Nothing to download; "ready" means a key is saved. The dictated text goes to the provider,
/// which the Settings row says in so many words.
@MainActor
final class HostedGrammarBackend: GrammarBackend {
    let provider: HostedProvider
    var modelID: String { provider.modelID }
    private(set) var isReady = false

    static let requestTimeout: Duration = .seconds(30)

    private let secrets: any SecretStore
    private let defaults: UserDefaults
    private let send: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    init(
        provider: HostedProvider, secrets: any SecretStore = KeychainSecretStore.shared,
        defaults: UserDefaults = .standard,
        send: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }
    ) {
        self.provider = provider
        self.secrets = secrets
        self.defaults = defaults
        self.send = send
    }

    // MARK: - Key and model

    var hasKey: Bool { secrets.secret(for: provider.rawValue)?.isEmpty == false }

    /// Saves the key (trimmed), or removes it when blank. A removed key unloads the backend.
    func setKey(_ key: String?) throws {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        try secrets.set(trimmed?.isEmpty == false ? trimmed : nil, for: provider.rawValue)
        if !hasKey { isReady = false }
    }

    /// The model name requests use: the user's, else the provider's default.
    var model: String {
        let custom = defaults.string(forKey: provider.modelKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? provider.defaultModel : custom
    }

    /// What the user typed, empty when they left the default.
    var customModel: String { defaults.string(forKey: provider.modelKey) ?? "" }

    func setModel(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { defaults.removeObject(forKey: provider.modelKey) } else { defaults.set(trimmed, forKey: provider.modelKey) }
    }

    // MARK: - GrammarBackend

    var availability: GrammarBackendAvailability {
        hasKey ? .available : .unavailable(reason: "Add your \(provider.displayName) API key.", settingsURL: nil)
    }

    func prepare(onProgress: @escaping @MainActor (Double) -> Void) async throws {
        guard hasKey else { throw HostedGrammarError.noKey(provider) }
        isReady = true
        onProgress(1)
    }

    func unload() {
        isReady = false
    }

    func correct(_ text: String, instructions: String, language: String?) async throws -> String {
        guard isReady else { throw GrammarBackendError.notReady }
        guard let key = secrets.secret(for: provider.rawValue), !key.isEmpty else { throw HostedGrammarError.noKey(provider) }
        let request = try HostedRequest.make(
            provider: provider, model: model, apiKey: key,
            system: HostedRequest.system(instructions: instructions, language: language), text: text,
            timeout: TimeInterval(Self.requestTimeout.components.seconds))
        let send = self.send
        let (data, response) = try await withGrammarTimeout(Self.requestTimeout) { try await send(request) }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HostedGrammarError.http(status: http.statusCode, detail: HostedRequest.errorDetail(from: data))
        }
        return try HostedRequest.text(from: data, provider: provider).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
