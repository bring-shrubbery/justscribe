//
//  InferenceGate.swift
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

/// Lets one request at a time use the speech model. Dictation's live passes, its final pass
/// and file chunks all go through it, in the order they arrive, so the model never serves
/// two requests at once.
///
/// A caller cancelled while it waits leaves the queue and gets `CancellationError`, so
/// dictation's timeout can fire while a file chunk holds the model. A caller cancelled after
/// it was handed the gate runs its body as usual and releases the gate when done.
final class InferenceGate {
    private var busy = false
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []

    /// How many callers are waiting for the gate.
    var queuedCount: Int { waiters.count }

    func run<T>(_ body: () async throws -> T) async throws -> T {
        try await acquire()
        defer { release() }
        return try await body()
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        if !busy {
            busy = true
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { waiters.append((id, $0)) }
        } onCancel: {
            // Runs on whichever thread cancelled the caller; the queue belongs to the main actor.
            Task { @MainActor in self.removeCancelledWaiter(id) }
        }
    }

    /// Wakes a cancelled caller, unless `release()` has already handed it the gate.
    private func removeCancelledWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }
}
