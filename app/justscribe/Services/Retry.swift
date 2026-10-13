//
//  Retry.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 05/10/2026.
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

/// Runs `body` again after a failure, up to `attempts` times in all, waiting `delay` before the
/// second attempt and twice as long before each one after. Stops early when the task is
/// cancelled. Throws the last error.
nonisolated enum Retry {
    static func attempting<T: Sendable>(
        _ attempts: Int, delay: Duration = .seconds(2), _ body: () async throws -> T
    ) async throws -> T {
        var wait = delay
        for attempt in 1...max(1, attempts) {
            do {
                return try await body()
            } catch {
                guard attempt < attempts, !Task.isCancelled else { throw error }
                print("Attempt \(attempt) failed (\(error.localizedDescription)); trying again in \(wait)")
                try? await Task.sleep(for: wait)
                wait *= 2
            }
        }
        fatalError("unreachable: every attempt returns or throws")
    }
}
