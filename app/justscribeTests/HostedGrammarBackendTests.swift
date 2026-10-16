//
//  HostedGrammarBackendTests.swift
//  justscribeTests
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
import Testing
@testable import justscribe

private final class MemorySecrets: SecretStore, @unchecked Sendable {
    var values: [String: String] = [:]
    func secret(for account: String) -> String? { values[account] }
    func set(_ secret: String?, for account: String) throws { values[account] = secret }
}

/// A class, so the throwaway defaults domain goes when the test ends.
@MainActor
final class HostedGrammarBackendTests {
    private let suiteName = "HostedGrammarBackendTests.\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let secrets = MemorySecrets()
    /// Every request sent, and the reply to give.
    private var sent: [URLRequest] = []
    private var reply: (status: Int, body: String) = (200, "")

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeBackend(_ provider: HostedProvider) -> HostedGrammarBackend {
        HostedGrammarBackend(provider: provider, secrets: secrets, defaults: defaults) { [unowned self] request in
            await MainActor.run { self.sent.append(request) }
            let reply = await MainActor.run { self.reply }
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil)!
            return (Data(reply.body.utf8), response)
        }
    }

    private func json(_ request: URLRequest) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]) ?? [:]
    }

    // MARK: - Requests

    @Test func aChatProviderGetsABearerTokenAndSystemPlusUserMessages() throws {
        let request = try HostedRequest.make(
            provider: .groq, model: "llama-3.3-70b-versatile", apiKey: "gsk_test", system: "Fix it.", text: "hello world", timeout: 30)
        #expect(request.url == URL(string: "https://api.groq.com/openai/v1/chat/completions"))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer gsk_test")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = json(request)
        #expect(body["model"] as? String == "llama-3.3-70b-versatile")
        let messages = body["messages"] as? [[String: String]]
        #expect(messages == [["role": "system", "content": "Fix it."], ["role": "user", "content": "hello world"]])
        #expect(body["temperature"] == nil, "some models reject a temperature; none is sent")
    }

    @Test func anthropicGetsItsOwnHeadersAndMessagesShape() throws {
        let request = try HostedRequest.make(
            provider: .anthropic, model: "claude-opus-5", apiKey: "sk-ant-test", system: "Fix it.", text: "hello", timeout: 30)
        #expect(request.url == URL(string: "https://api.anthropic.com/v1/messages"))
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        let body = json(request)
        #expect(body["model"] as? String == "claude-opus-5")
        #expect(body["system"] as? String == "Fix it.")
        #expect(body["max_tokens"] as? Int == HostedRequest.maxOutputTokens)
        #expect(body["messages"] as? [[String: String]] == [["role": "user", "content": "hello"]])
    }

    @Test func theSystemPromptFramesTheInstructionsAndNamesANonEnglishLanguage() {
        let english = HostedRequest.system(instructions: "Be brief.", language: "en")
        #expect(english == GrammarPrompt.frame("Be brief."))
        #expect(HostedRequest.system(instructions: "Be brief.", language: nil) == english)
        let german = HostedRequest.system(instructions: "Be brief.", language: "de")
        #expect(german.hasPrefix(english) && german.contains("\"de\""))
    }

    // MARK: - Replies

    @Test func theChatReplyIsTheFirstChoicesMessage() throws {
        let data = Data(#"{"choices":[{"message":{"role":"assistant","content":"Hello, world."}}]}"#.utf8)
        #expect(try HostedRequest.text(from: data, provider: .openai) == "Hello, world.")
    }

    @Test func theAnthropicReplyJoinsItsTextBlocks() throws {
        let data = Data(#"{"content":[{"type":"thinking","thinking":"…"},{"type":"text","text":"Hello, "},{"type":"text","text":"world."}]}"#.utf8)
        #expect(try HostedRequest.text(from: data, provider: .anthropic) == "Hello, world.")
    }

    @Test func anUnreadableOrEmptyReplyIsAnError() {
        #expect(throws: HostedGrammarError.badResponse) { try HostedRequest.text(from: Data("nope".utf8), provider: .groq) }
        #expect(throws: HostedGrammarError.badResponse) { try HostedRequest.text(from: Data("{}".utf8), provider: .anthropic) }
        let blank = Data(#"{"choices":[{"message":{"content":"  \n"}}]}"#.utf8)
        #expect(throws: HostedGrammarError.emptyResponse) { try HostedRequest.text(from: blank, provider: .groq) }
    }

    @Test func theErrorDetailComesFromTheErrorMessage() {
        #expect(HostedRequest.errorDetail(from: Data(#"{"error":{"message":"Invalid API Key","type":"invalid_request_error"}}"#.utf8)) == "Invalid API Key")
        #expect(HostedRequest.errorDetail(from: Data("{}".utf8)) == nil)
    }

    // MARK: - The backend

    @Test func withoutAKeyTheBackendIsUnavailableAndWillNotPrepare() async {
        let backend = makeBackend(.groq)
        #expect(!backend.hasKey)
        #expect(backend.availability == .unavailable(reason: "Add your Groq API key.", settingsURL: nil))
        await #expect(throws: HostedGrammarError.noKey(.groq)) { try await backend.prepare { _ in } }
        #expect(!backend.isReady)
    }

    @Test func aSavedKeyIsTrimmedMakesItAvailableAndIsUsedInRequests() async throws {
        let backend = makeBackend(.openai)
        try backend.setKey("  sk-test \n")
        #expect(secrets.values["openai"] == "sk-test")
        #expect(backend.availability == .available)
        try await backend.prepare { _ in }
        #expect(backend.isReady)

        reply = (200, #"{"choices":[{"message":{"content":"  Hello, world.\n"}}]}"#)
        let out = try await backend.correct("hello world", instructions: "Fix it.", language: nil)
        #expect(out == "Hello, world.")
        #expect(sent.count == 1)
        #expect(sent.first?.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(json(sent[0])["model"] as? String == HostedProvider.openai.defaultModel)
    }

    @Test func theModelNameIsTheUsersWhenTypedElseTheProvidersDefault() throws {
        let backend = makeBackend(.groq)
        #expect(backend.model == HostedProvider.groq.defaultModel)
        #expect(backend.customModel == "")
        backend.setModel("  llama-3.1-8b-instant ")
        #expect(backend.model == "llama-3.1-8b-instant")
        #expect(backend.customModel == "llama-3.1-8b-instant")
        backend.setModel("   ")
        #expect(backend.model == HostedProvider.groq.defaultModel)
        #expect(defaults.string(forKey: HostedProvider.groq.modelKey) == nil)
    }

    @Test func aRejectedKeyIsReportedAndNothingIsCorrected() async throws {
        let backend = makeBackend(.anthropic)
        try backend.setKey("sk-ant-bad")
        try await backend.prepare { _ in }
        reply = (401, #"{"error":{"type":"authentication_error","message":"invalid x-api-key"}}"#)
        await #expect(throws: HostedGrammarError.http(status: 401, detail: "invalid x-api-key")) {
            try await backend.correct("hello", instructions: "", language: nil)
        }
        #expect(HostedGrammarError.http(status: 401, detail: nil).errorDescription == "The provider rejected the API key.")
    }

    @Test func removingTheKeyUnloadsTheBackend() async throws {
        let backend = makeBackend(.mistral)
        try backend.setKey("key")
        try await backend.prepare { _ in }
        try backend.setKey(nil)
        #expect(!backend.hasKey && !backend.isReady)
        #expect(secrets.values["mistral"] == nil)
        await #expect(throws: GrammarBackendError.self) { try await backend.correct("x", instructions: "", language: nil) }
    }

    // MARK: - Model IDs

    @Test func everyProviderIsAGrammarModelFoundByItsID() {
        for provider in HostedProvider.allCases {
            let model = GrammarCorrectionModel.model(forID: provider.modelID)
            #expect(model?.backend == .hosted(provider), "\(provider)")
            #expect(model?.approximateRAMInMB == nil, "\(provider): nothing of ours in memory")
            #expect(HostedProvider.provider(forModelID: provider.modelID) == provider)
        }
        #expect(HostedProvider.provider(forModelID: "apple-foundation") == nil)
        #expect(AppSettings.normalizedGrammarModelID("hosted:groq") == "hosted:groq")
        #expect(AppSettings.normalizedGrammarModelID("hosted:nope") == "apple-foundation")
    }
}
