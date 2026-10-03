//
//  GrammarBackend.swift
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

/// Whether a grammar model can be used right now, and if not, why.
nonisolated enum GrammarBackendAvailability: Equatable {
    /// Usable immediately.
    case available
    /// Usable, but the weights have to be downloaded first.
    case requiresDownload
    /// Not usable. `reason` is user-facing; `settingsURL` opens the pane that fixes it.
    case unavailable(reason: String, settingsURL: URL?)
}

nonisolated enum GrammarBackendError: LocalizedError {
    case notReady
    case modelNotFound
    case notDeletable
    case unavailable(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "Grammar correction model is not loaded."
        case .modelNotFound:
            return "Grammar correction model not found."
        case .notDeletable:
            return "This model is part of macOS and cannot be deleted."
        case .unavailable(let reason):
            return reason
        case .timeout:
            return "Grammar correction timed out."
        }
    }
}

/// One grammar correction engine. Implementations are singletons owned by
/// `GrammarCorrectionService`, which is the only thing that talks to them.
@MainActor
protocol GrammarBackend: AnyObject {
    /// The `GrammarCorrectionModel.id` this backend serves.
    var modelID: String { get }
    var availability: GrammarBackendAvailability { get }
    /// True once `prepare` has succeeded and `correct` can be called.
    var isReady: Bool { get }

    /// Download if necessary and get ready to correct. `onProgress` receives 0...1.
    func prepare(onProgress: @escaping @MainActor (Double) -> Void) async throws
    func correct(_ text: String, instructions: String, language: String?) async throws -> String
    func unload()
}

/// Race `operation` against a timer so a wedged model can't hang a dictation.
///
/// `T` must be `Sendable`; in practice callers pass `String`. Note that
/// `LanguageModelSession.Response` is *not* `Sendable`, so extract `.content`
/// inside the closure rather than returning the response itself.
func withGrammarTimeout<T: Sendable>(
    _ duration: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw GrammarBackendError.timeout
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
