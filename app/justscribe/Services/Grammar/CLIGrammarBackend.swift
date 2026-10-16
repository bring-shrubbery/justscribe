//
//  CLIGrammarBackend.swift
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

/// Clean-up through a coding agent's command-line tool on this Mac, signed in to the user's
/// own account: one instance per `CLIAgent`. "Ready" means the tool is installed where the
/// app can see it; whether the sign-in works shows on the first request, which Settings lets
/// the user try before dictating.
@MainActor
final class CLIGrammarBackend: GrammarBackend {
    let agent: CLIAgent
    var modelID: String { agent.modelID }
    private(set) var isReady = false

    /// Starting the tool takes a few seconds before the model answers.
    static let requestTimeout: Duration = .seconds(90)

    private let defaults: UserDefaults
    private let home: String
    private let tmp: String
    private let locate: @MainActor () -> String?
    private let run: @Sendable (CLIInvocation, Duration) async throws -> CommandResult

    init(
        agent: CLIAgent, defaults: UserDefaults = .standard,
        home: String = CLIAgent.realHome, tmp: String = NSTemporaryDirectory(),
        locate: (@MainActor () -> String?)? = nil,
        run: @escaping @Sendable (CLIInvocation, Duration) async throws -> CommandResult = { try await CommandRunner.run($0, timeout: $1) }
    ) {
        self.agent = agent
        self.defaults = defaults
        self.home = home
        self.tmp = tmp
        self.locate = locate ?? { agent.locate(home: home) }
        self.run = run
    }

    /// Where the tool is, looked up afresh each time so an install made while the app runs
    /// is seen.
    var executablePath: String? { locate() }
    var isInstalled: Bool { executablePath != nil }

    /// What the user typed, empty for the tool's own default.
    var model: String { defaults.string(forKey: agent.modelKey) ?? "" }

    func setModel(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { defaults.removeObject(forKey: agent.modelKey) } else { defaults.set(trimmed, forKey: agent.modelKey) }
    }

    // MARK: - GrammarBackend

    var availability: GrammarBackendAvailability {
        isInstalled ? .available : .unavailable(reason: "\(agent.displayName) isn't installed.", settingsURL: nil)
    }

    func prepare(onProgress: @escaping @MainActor (Double) -> Void) async throws {
        guard isInstalled else { throw CLIGrammarError.notInstalled(agent) }
        isReady = true
        onProgress(1)
    }

    func unload() {
        isReady = false
    }

    func correct(_ text: String, instructions: String, language: String?) async throws -> String {
        guard isReady else { throw GrammarBackendError.notReady }
        guard let executable = executablePath else { throw CLIGrammarError.notInstalled(agent) }
        let invocation = CLIInvocation.make(
            agent: agent, executable: executable, model: model,
            system: HostedRequest.system(instructions: instructions, language: language), text: text,
            home: home, tmp: tmp)
        defer { if let file = invocation.outputFile { try? FileManager.default.removeItem(atPath: file) } }
        let result = try await run(invocation, Self.requestTimeout)
        if result.timedOut { throw CLIGrammarError.timedOut(agent) }
        guard result.status == 0 else {
            throw CLIGrammarError.failed(agent, status: result.status, detail: Self.detail(from: result))
        }
        let answer: String
        if let file = invocation.outputFile {
            answer = (try? String(contentsOfFile: file, encoding: .utf8)) ?? ""
        } else {
            answer = result.stdout
        }
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CLIGrammarError.noOutput(agent) }
        return trimmed
    }

    /// The last line the tool said, for a failure message: stderr first, then stdout.
    nonisolated static func detail(from result: CommandResult) -> String {
        for output in [result.stderr, result.stdout] {
            let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            if let last = lines.last(where: { !$0.isEmpty }) { return String(last.prefix(200)) }
        }
        return ""
    }
}
