//
//  CLIGrammarBackendTests.swift
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

/// A class, so the throwaway defaults domain and folder go when the test ends.
@MainActor
final class CLIGrammarBackendTests {
    private let suiteName = "CLIGrammarBackendTests.\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("CLIGrammarBackendTests-\(UUID().uuidString)", isDirectory: true).path
    /// Every invocation run, and the result to give.
    private var runs: [CLIInvocation] = []
    private var result = CommandResult(status: 0, stdout: "", stderr: "", timedOut: false)
    /// What the fake file system says about the tool.
    private var installedAt: String? = "/opt/homebrew/bin/tool"

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
        try? FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(atPath: tmp)
    }

    private func makeBackend(_ agent: CLIAgent) -> CLIGrammarBackend {
        CLIGrammarBackend(
            agent: agent, defaults: defaults, home: "/Users/someone", tmp: tmp,
            locate: { [unowned self] in self.installedAt },
            run: { [unowned self] invocation, _ in
                await MainActor.run { self.runs.append(invocation) }
                let result = await MainActor.run { self.result }
                // Codex writes its answer to the file it was given.
                if let file = invocation.outputFile, result.status == 0, !result.timedOut {
                    try result.stdout.write(toFile: file, atomically: true, encoding: .utf8)
                }
                return result
            })
    }

    // MARK: - Finding the tool

    @Test func theToolIsLookedForInTheUsualPlacesNewestNodeFirst() {
        let home = "/Users/someone"
        let claude = CLIAgent.claude.candidatePaths(home: home) { dir in
            dir == "\(home)/.nvm/versions/node" ? ["v22.1.0", "v24.18.0"] : []
        }
        #expect(claude.first == "\(home)/.local/bin/claude")
        #expect(claude.contains("\(home)/.claude/local/claude"))
        #expect(claude.contains("/opt/homebrew/bin/claude") && claude.contains("/usr/local/bin/claude"))
        let nvm = claude.filter { $0.contains("/.nvm/") }
        #expect(nvm == ["\(home)/.nvm/versions/node/v24.18.0/bin/claude", "\(home)/.nvm/versions/node/v22.1.0/bin/claude"])
        #expect(CLIAgent.codex.candidatePaths(home: home) { _ in [] }.contains("/opt/homebrew/bin/codex"))
        #expect(!CLIAgent.codex.candidatePaths(home: home) { _ in [] }.contains("\(home)/.claude/local/codex"))
    }

    @Test func locateFindsAnExecutableFileAndNothingElse() throws {
        let home = tmp
        let bin = "\(home)/.local/bin"
        try FileManager.default.createDirectory(atPath: bin, withIntermediateDirectories: true)
        #expect(CLIAgent.claude.locate(home: home) == nil)
        try "#!/bin/sh\necho hi".write(toFile: "\(bin)/claude", atomically: true, encoding: .utf8)
        #expect(CLIAgent.claude.locate(home: home) == nil, "a file that is not executable is not the tool")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: "\(bin)/claude")
        #expect(CLIAgent.claude.locate(home: home) == "\(bin)/claude")
    }

    @Test func aMissingToolIsUnavailableAndWillNotPrepare() async {
        installedAt = nil
        let backend = makeBackend(.codex)
        #expect(!backend.isInstalled)
        #expect(backend.availability == .unavailable(reason: "Codex CLI isn't installed.", settingsURL: nil))
        await #expect(throws: CLIGrammarError.notInstalled(.codex)) { try await backend.prepare { _ in } }
        #expect(!backend.isReady)
    }

    // MARK: - How the tools are called

    @Test func claudeIsCalledInPrintModeWithTheSystemPromptAndNoToolsOrSessions() {
        let call = CLIInvocation.make(
            agent: .claude, executable: "/Users/someone/.local/bin/claude", model: " sonnet ", system: "Fix it.", text: "hello world",
            home: "/Users/someone", tmp: "/tmp/container")
        #expect(call.executable == "/Users/someone/.local/bin/claude")
        #expect(call.arguments == [
            "-p", "hello world", "--system-prompt", "Fix it.", "--output-format", "text",
            "--no-session-persistence", "--tools", "", "--model", "sonnet",
        ])
        #expect(call.environment["CLAUDE_CONFIG_DIR"] == "/Users/someone/.claude")
        #expect(call.environment["TMPDIR"] == "/tmp/container")
        #expect(call.environment["PATH"]?.hasPrefix("/Users/someone/.local/bin:") == true)
        #expect(call.environment["HOME"] == nil, "the container stays the home; only the config folder is named")
        #expect(call.outputFile == nil)
        let noModel = CLIInvocation.make(agent: .claude, executable: "/x/claude", model: nil, system: "s", text: "t", home: "/h", tmp: "/t")
        #expect(!noModel.arguments.contains("--model"))
    }

    @Test func codexIsCalledInExecModeWritingItsAnswerToAFileInTheContainer() {
        let call = CLIInvocation.make(
            agent: .codex, executable: "/opt/homebrew/bin/codex", model: "", system: "Fix it.", text: "hello world",
            home: "/Users/someone", tmp: "/tmp/container", outputName: "abc")
        #expect(call.arguments == [
            "exec", "--skip-git-repo-check", "--sandbox", "read-only", "--ephemeral",
            "--cd", "/tmp/container", "--output-last-message", "/tmp/container/justscribe-codex-abc.txt",
            "Fix it.\n\nhello world",
        ])
        #expect(call.environment["CODEX_HOME"] == "/Users/someone/.codex")
        #expect(call.environment["TMPDIR"] == "/tmp/container")
        #expect(call.outputFile == "/tmp/container/justscribe-codex-abc.txt")
        let withModel = CLIInvocation.make(agent: .codex, executable: "/x/codex", model: "gpt-5", system: "s", text: "t", home: "/h", tmp: "/t")
        #expect(withModel.arguments.contains("--model") && withModel.arguments.contains("gpt-5"))
        #expect(withModel.arguments.last == "s\n\nt")
    }

    // MARK: - The backend

    @Test func claudesAnswerComesFromStdoutTrimmed() async throws {
        let backend = makeBackend(.claude)
        try await backend.prepare { _ in }
        result = CommandResult(status: 0, stdout: "  Hello, world.\n", stderr: "", timedOut: false)
        let out = try await backend.correct("hello world", instructions: "Fix it.", language: nil)
        #expect(out == "Hello, world.")
        #expect(runs.count == 1)
        #expect(runs[0].arguments.prefix(2) == ["-p", "hello world"])
        #expect(runs[0].arguments[3] == HostedRequest.system(instructions: "Fix it.", language: nil))
    }

    @Test func codexsAnswerComesFromItsOutputFileWhichIsThenRemoved() async throws {
        let backend = makeBackend(.codex)
        backend.setModel("gpt-5")
        try await backend.prepare { _ in }
        result = CommandResult(status: 0, stdout: "Hello, world.\n", stderr: "banner noise", timedOut: false)
        let out = try await backend.correct("hello world", instructions: "Fix it.", language: "de")
        #expect(out == "Hello, world.")
        let file = try #require(runs.first?.outputFile)
        #expect(!FileManager.default.fileExists(atPath: file))
        #expect(runs[0].arguments.contains("gpt-5"))
        #expect(runs[0].arguments.last?.contains("\"de\"") == true)
    }

    @Test func aFailureTimeoutOrEmptyAnswerIsReported() async throws {
        let backend = makeBackend(.claude)
        try await backend.prepare { _ in }
        result = CommandResult(status: 1, stdout: "", stderr: "Failed to authenticate: OAuth session expired\n", timedOut: false)
        await #expect(throws: CLIGrammarError.failed(.claude, status: 1, detail: "Failed to authenticate: OAuth session expired")) {
            try await backend.correct("x", instructions: "", language: nil)
        }
        result = CommandResult(status: -1, stdout: "", stderr: "", timedOut: true)
        await #expect(throws: CLIGrammarError.timedOut(.claude)) { try await backend.correct("x", instructions: "", language: nil) }
        result = CommandResult(status: 0, stdout: " \n", stderr: "", timedOut: false)
        await #expect(throws: CLIGrammarError.noOutput(.claude)) { try await backend.correct("x", instructions: "", language: nil) }
        #expect(CLIGrammarError.failed(.claude, status: 1, detail: "boom").errorDescription == "Claude Code: boom")
        #expect(CLIGrammarError.failed(.codex, status: 2, detail: "").errorDescription == "Codex CLI failed (exit 2).")
    }

    @Test func theModelIsKeptPerAgentAndBlankOrTheDefaultMeansTheCheapDefault() async throws {
        let backend = makeBackend(.claude)
        #expect(backend.model == "haiku" && backend.customModel == "")
        backend.setModel("  sonnet ")
        #expect(backend.model == "sonnet")
        #expect(makeBackend(.codex).model == CLIAgent.codex.defaultModel)
        backend.setModel(" ")
        #expect(backend.model == "haiku" && defaults.string(forKey: CLIAgent.claude.modelKey) == nil)
        backend.setModel("haiku")
        #expect(defaults.string(forKey: CLIAgent.claude.modelKey) == nil)

        // A request with nothing chosen goes to the default, never to the tool's own.
        try await backend.prepare { _ in }
        result = CommandResult(status: 0, stdout: "Hi.", stderr: "", timedOut: false)
        _ = try await backend.correct("hi", instructions: "", language: nil)
        #expect(runs.last?.arguments.suffix(2) == ["--model", "haiku"])
    }

    @Test func aRetiredModelsFailureReadsAsWords() {
        // As the tools printed it for a model name that does not exist (2026-10-17).
        let claude = CommandResult(
            status: 1,
            stdout: "There's an issue with the selected model (claude-retired-1). It may not exist or you may not have access to it.\n",
            stderr: "\"claude-retired-1\" isn't described by this version's model catalog\n[claude-code:unrecognized_model] {\"model\":\"claude-retired-1\"}\n",
            timedOut: false)
        #expect(CLIGrammarBackend.detail(from: claude).hasPrefix("There's an issue with the selected model (claude-retired-1)."))
        let codex = CommandResult(
            status: 1, stdout: "",
            stderr: #"ERROR: {"type":"error","status":400,"error":{"type":"invalid_request_error","message":"The 'gpt-retired-1' model is not supported when using Codex with a ChatGPT account."}}"# + "\n",
            timedOut: false)
        #expect(CLIGrammarBackend.detail(from: codex) == "The 'gpt-retired-1' model is not supported when using Codex with a ChatGPT account.")
        let quoted = CommandResult(status: 1, stdout: "", stderr: #"{"message":"Say \"hi\" first"}"#, timedOut: false)
        #expect(CLIGrammarBackend.detail(from: quoted) == "Say \"hi\" first")
    }

    @Test func everyAgentOffersItsDefaultAmongItsModels() {
        for agent in CLIAgent.allCases {
            let models = agent.availableModels(home: tmp)
            #expect(models.first?.id == agent.defaultModel, "\(agent)")
            #expect(Set(models.map(\.id)).count == models.count, "\(agent)")
        }
    }

    @Test func codexsModelsComeFromItsCacheInItsOrderWithoutHiddenOnes() throws {
        let cache = """
        {"fetched_at": "2026-10-17T17:50:02Z", "models": [
          {"slug": "gpt-6-luna", "display_name": "GPT-6-Luna", "description": "Fast.", "visibility": "list", "priority": 4},
          {"slug": "gpt-6.1-sol", "display_name": "GPT-6.1-Sol", "description": "Workhorse.", "visibility": "list", "priority": 1, "extra": [1]},
          {"slug": "codex-auto-review", "display_name": "Review", "visibility": "hide", "priority": 2}
        ]}
        """
        let models = try #require(CLIAgent.codexModels(fromCache: Data(cache.utf8)))
        #expect(models.map(\.id) == ["gpt-6.1-sol", "gpt-6-luna"])
        #expect(models[0] == CLIModelOption(id: "gpt-6.1-sol", name: "GPT-6.1-Sol", detail: "Workhorse."))
        #expect(CLIAgent.codexModels(fromCache: Data("not json".utf8)) == nil)

        // Read from the Codex folder under the home it is given; a cache without the
        // default still offers it, first.
        try FileManager.default.createDirectory(atPath: "\(tmp)/.codex", withIntermediateDirectories: true)
        let other = #"{"models": [{"slug": "gpt-7", "visibility": "list"}]}"#
        try other.write(toFile: "\(tmp)/.codex/models_cache.json", atomically: true, encoding: .utf8)
        #expect(CLIAgent.codex.availableModels(home: tmp).map(\.id) == [CLIAgent.codex.defaultModel, "gpt-7"])
        #expect(CLIAgent.claude.availableModels(home: tmp) == CLIAgent.claude.builtInModels)
    }

    @Test func everyAgentIsAGrammarModelFoundByItsID() {
        for agent in CLIAgent.allCases {
            let model = GrammarCorrectionModel.model(forID: agent.modelID)
            #expect(model?.backend == .cli(agent), "\(agent)")
            #expect(model?.approximateRAMInMB == nil)
            #expect(CLIAgent.agent(forModelID: agent.modelID) == agent)
        }
        #expect(CLIAgent.agent(forModelID: "hosted:groq") == nil)
        #expect(AppSettings.normalizedGrammarModelID("cli:codex") == "cli:codex")
    }

    // MARK: - Running commands

    @Test func theRunnerCollectsOutputAndStatus() async throws {
        let result = try await CommandRunner.run(executable: "/bin/sh", arguments: ["-c", "echo out; echo err 1>&2; exit 3"], environment: [:], timeout: .seconds(10))
        #expect(result.status == 3 && !result.timedOut)
        #expect(result.stdout == "out\n" && result.stderr == "err\n")
    }

    @Test func theRunnerKillsACommandPastItsDeadline() async throws {
        let started = ContinuousClock.now
        let result = try await CommandRunner.run(executable: "/bin/sleep", arguments: ["30"], environment: [:], timeout: .milliseconds(300))
        #expect(result.timedOut)
        #expect(ContinuousClock.now - started < .seconds(5))
    }

    @Test func aMissingExecutableThrows() async {
        await #expect(throws: (any Error).self) {
            try await CommandRunner.run(executable: "/nonexistent/tool", arguments: [], environment: [:], timeout: .seconds(1))
        }
    }
}
