//
//  CLIAgent.swift
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

/// A coding agent's command-line tool already on the Mac, signed in to the user's own
/// account, used for clean-up the way a hosted provider is. The app runs it as a child
/// process; the sandbox lets that process read the tool and its own configuration folder
/// through the exceptions in `justscribe.entitlements`, and nothing else of the home folder.
nonisolated enum CLIAgent: String, CaseIterable, Codable, Sendable, Identifiable {
    case claude
    case codex

    var id: String { rawValue }

    /// The grammar model ID this agent is selected under: "cli:claude".
    var modelID: String { "\(Self.modelIDPrefix)\(rawValue)" }
    static let modelIDPrefix = "cli:"

    static func agent(forModelID id: String) -> CLIAgent? {
        guard id.hasPrefix(modelIDPrefix) else { return nil }
        return CLIAgent(rawValue: String(id.dropFirst(modelIDPrefix.count)))
    }

    /// The model the user picked or typed for this agent; unset means `defaultModel`.
    var modelKey: String { "grammar.cli.model.\(rawValue)" }

    /// The fast, cheap model clean-up uses unless the user picks another: tidying a
    /// sentence needs no frontier model, and every dictation spends the user's own quota.
    var defaultModel: String {
        switch self {
        case .claude: "haiku"
        case .codex: "gpt-6-luna"
        }
    }

    /// The models offered in Settings when nothing better is known. Claude Code takes
    /// aliases that always mean the latest of each family, so its list does not go stale.
    var builtInModels: [CLIModelOption] {
        switch self {
        case .claude:
            [
                CLIModelOption(id: "haiku", name: "Haiku", detail: "Fastest and cheapest"),
                CLIModelOption(id: "sonnet", name: "Sonnet", detail: "Balanced"),
                CLIModelOption(id: "opus", name: "Opus", detail: "Most capable"),
                CLIModelOption(id: "fable", name: "Fable", detail: "Frontier"),
            ]
        case .codex:
            [
                CLIModelOption(id: "gpt-6-luna", name: "GPT-6-Luna", detail: "Fast and affordable"),
                CLIModelOption(id: "gpt-6.1-sol", name: "GPT-6.1-Sol", detail: "Workhorse"),
                CLIModelOption(id: "gpt-6-astra", name: "GPT-6-Astra", detail: "Frontier"),
            ]
        }
    }

    /// The models this agent offers right now. Codex keeps the list its account can use in
    /// `models_cache.json`, refreshed whenever it runs, so that list is read when it is there;
    /// otherwise, and for Claude, the built-in one. The default is always on the list.
    func availableModels(home: String = CLIAgent.realHome) -> [CLIModelOption] {
        var models = builtInModels
        if self == .codex,
           let data = FileManager.default.contents(atPath: "\(home)/.codex/models_cache.json"),
           let cached = Self.codexModels(fromCache: data), !cached.isEmpty {
            models = cached
        }
        if !models.contains(where: { $0.id == defaultModel }),
           let builtIn = builtInModels.first(where: { $0.id == defaultModel }) {
            models.insert(builtIn, at: 0)
        }
        return models
    }

    /// The models Codex lists for the account, in its own order; hidden ones left out.
    static func codexModels(fromCache data: Data) -> [CLIModelOption]? {
        struct Cache: Decodable {
            struct Model: Decodable {
                var slug: String
                var display_name: String?
                var description: String?
                var visibility: String?
                var priority: Int?
            }
            var models: [Model]
        }
        guard let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return nil }
        return cache.models
            .filter { $0.visibility == nil || $0.visibility == "list" }
            .enumerated()
            .sorted { ($0.element.priority ?? Int.max, $0.offset) < ($1.element.priority ?? Int.max, $1.offset) }
            .map { CLIModelOption(id: $0.element.slug, name: $0.element.display_name ?? $0.element.slug,
                                  detail: $0.element.description ?? "") }
    }

    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex CLI"
        }
    }

    var commandName: String { rawValue }

    var accountName: String {
        switch self {
        case .claude: "your Anthropic account"
        case .codex: "your OpenAI account"
        }
    }

    var installURL: URL {
        switch self {
        case .claude: URL(string: "https://claude.ai/code")!
        case .codex: URL(string: "https://developers.openai.com/codex/cli")!
        }
    }

    var grammarModel: GrammarCorrectionModel {
        GrammarCorrectionModel(
            id: modelID, displayName: displayName, provider: "On this Mac · \(accountName)", backend: .cli(self),
            hubID: nil, approximateSize: nil, approximateRAM: nil, approximateRAMInMB: nil)
    }

    /// The user's real home folder. In the sandbox `NSHomeDirectory()` is the container.
    static var realHome: String {
        if let dir = getpwuid(getuid())?.pointee.pw_dir { return String(cString: dir) }
        return NSHomeDirectory()
    }

    /// Where the tool is usually installed, most likely first. Every folder here is one the
    /// entitlements let the app read, and so must be wherever a link here points: Claude's
    /// native installer links `~/.local/bin/claude` into `~/.local/share/claude/versions/`.
    /// An install elsewhere is not seen.
    func candidatePaths(home: String, contentsOf list: (String) -> [String]) -> [String] {
        let name = commandName
        var paths: [String] = []
        switch self {
        case .claude:
            paths += ["\(home)/.local/bin/\(name)", "\(home)/.claude/local/\(name)"]
        case .codex:
            paths += ["\(home)/.local/bin/\(name)"]
        }
        paths += ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"]
        // Node version managers keep one bin folder per Node version; newest first.
        let nvm = "\(home)/.nvm/versions/node"
        for version in list(nvm).sorted(by: >) { paths.append("\(nvm)/\(version)/bin/\(name)") }
        paths += ["\(home)/.volta/bin/\(name)", "\(home)/.npm-global/bin/\(name)"]
        return paths
    }

    /// The first candidate that is an executable file, or nil when the tool is not installed
    /// anywhere the app can see.
    func locate(home: String = CLIAgent.realHome, fileManager: FileManager = .default) -> String? {
        let list: (String) -> [String] = { (try? fileManager.contentsOfDirectory(atPath: $0)) ?? [] }
        return candidatePaths(home: home, contentsOf: list).first { fileManager.isExecutableFile(atPath: $0) }
    }
}

/// One model an agent's tool can be asked for, as Settings lists it.
nonisolated struct CLIModelOption: Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var detail: String
}

nonisolated enum CLIGrammarError: LocalizedError, Equatable {
    case notInstalled(CLIAgent)
    case timedOut(CLIAgent)
    case failed(CLIAgent, status: Int32, detail: String)
    case noOutput(CLIAgent)

    var errorDescription: String? {
        switch self {
        case .notInstalled(let agent): "\(agent.displayName) isn't installed."
        case .timedOut(let agent): "\(agent.displayName) didn't answer in time."
        case .failed(let agent, let status, let detail):
            detail.isEmpty ? "\(agent.displayName) failed (exit \(status))." : "\(agent.displayName): \(detail)"
        case .noOutput(let agent): "\(agent.displayName) sent no text back."
        }
    }
}

/// How the tool is called: arguments, environment, and where its answer lands. Pure, so the
/// shape is tested without running anything.
nonisolated struct CLIInvocation: Equatable, Sendable {
    var executable: String
    var arguments: [String]
    var environment: [String: String]
    /// A file the tool writes its answer to, read after it exits; nil means stdout.
    var outputFile: String?

    /// `tmp` is the container's temporary folder: the only place a child may write freely.
    static func make(
        agent: CLIAgent, executable: String, model: String?, system: String, text: String, home: String, tmp: String,
        outputName: String = UUID().uuidString
    ) -> CLIInvocation {
        let binDir = (executable as NSString).deletingLastPathComponent
        var environment = [
            "PATH": "\(binDir):/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin",
            "TMPDIR": tmp,
            "NO_COLOR": "1",
            "TERM": "dumb",
        ]
        let modelName = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch agent {
        case .claude:
            // The configuration folder is named outright: `HOME` is the container, and the
            // sign-in lives in the real one. No tools leaves a plain answer, and nothing is
            // written for the session. Not `--bare`: bare mode skips the stored sign-in too,
            // and answers "Not logged in". Its scratch folder ignores `TMPDIR` and defaults to
            // `/tmp/claude-<uid>`, which the sandbox refuses (EPERM), so it is named too.
            environment["CLAUDE_CONFIG_DIR"] = "\(home)/.claude"
            environment["CLAUDE_CODE_TMPDIR"] = tmp
            var arguments = [
                "-p", text, "--system-prompt", system, "--output-format", "text",
                "--no-session-persistence", "--tools", "",
            ]
            if !modelName.isEmpty { arguments += ["--model", modelName] }
            return CLIInvocation(executable: executable, arguments: arguments, environment: environment, outputFile: nil)
        case .codex:
            // Codex has no system prompt of its own in exec mode; the frame goes first. Its
            // scratch files go to the container's tmp, its session is not kept, and the last
            // message is read from a file rather than picked out of its banner.
            environment["CODEX_HOME"] = "\(home)/.codex"
            let output = "\(tmp)/justscribe-codex-\(outputName).txt"
            var arguments = [
                "exec", "--skip-git-repo-check", "--sandbox", "read-only", "--ephemeral",
                "--cd", tmp, "--output-last-message", output,
            ]
            if !modelName.isEmpty { arguments += ["--model", modelName] }
            arguments.append(system + "\n\n" + text)
            return CLIInvocation(executable: executable, arguments: arguments, environment: environment, outputFile: output)
        }
    }
}
