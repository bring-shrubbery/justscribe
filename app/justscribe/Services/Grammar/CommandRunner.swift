//
//  CommandRunner.swift
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

nonisolated struct CommandResult: Sendable, Equatable {
    var status: Int32
    var stdout: String
    var stderr: String
    var timedOut: Bool
}

/// Runs a command to completion off the main actor, with a hard deadline. Output is drained
/// as it comes, so a helper the command leaves holding the pipe cannot block the app, and a
/// command past its deadline is killed outright.
nonisolated enum CommandRunner {
    private final class Buffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func append(_ more: Data) { lock.lock(); data += more; lock.unlock() }
        var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        /// True the first time only.
        func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
    }

    @concurrent
    static func run(_ invocation: CLIInvocation, timeout: Duration) async throws -> CommandResult {
        try await run(executable: invocation.executable, arguments: invocation.arguments,
                      environment: invocation.environment, timeout: timeout)
    }

    @concurrent
    static func run(executable: String, arguments: [String], environment: [String: String], timeout: Duration) async throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let stdout = Buffer(), stderr = Buffer()
        out.fileHandleForReading.readabilityHandler = { stdout.append($0.availableData) }
        err.fileHandleForReading.readabilityHandler = { stderr.append($0.availableData) }
        defer {
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
        }

        let once = Once()
        let timedOut: Bool = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { _ in
                if once.claim() { continuation.resume(returning: false) }
            }
            do {
                try process.run()
            } catch {
                if once.claim() { continuation.resume(throwing: error) }
                return
            }
            let pid = process.processIdentifier
            let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                guard once.claim() else { return }
                kill(pid, SIGKILL)
                continuation.resume(returning: true)
            }
        }
        if timedOut {
            // Let the kill land, so the status below is the real one.
            try? await Task.sleep(for: .milliseconds(200))
        }
        // Whatever is left in the pipes after exit.
        stdout.append(out.fileHandleForReading.availableData)
        stderr.append(err.fileHandleForReading.availableData)
        return CommandResult(status: process.isRunning ? -1 : process.terminationStatus,
                             stdout: stdout.text, stderr: stderr.text, timedOut: timedOut)
    }
}
