//
//  DiagnosticsLog.swift
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
import Observation

/// The last few dictation sessions, newest first, in `diagnostics.json` in the container, so
/// Settings can show them and the user can copy a report.
@Observable
final class DiagnosticsLog {
    static let capacity = 20
    static let shared = DiagnosticsLog(fileURL: JSONFile.containerURL("diagnostics.json"))

    private(set) var sessions: [SessionDiagnostic] = []
    private let fileURL: URL

    init(fileURL: URL) { self.fileURL = fileURL }

    func load() {
        if case .loaded(let file) = JSONFile.read(DiagnosticsFile.self, from: fileURL) {
            sessions = Array(file.sessions.prefix(Self.capacity))
        } else {
            sessions = []
        }
    }

    func record(_ session: SessionDiagnostic) {
        sessions.insert(session, at: 0)
        if sessions.count > Self.capacity { sessions.removeLast(sessions.count - Self.capacity) }
        JSONFile.write(DiagnosticsFile(version: DiagnosticsFile.currentVersion, sessions: sessions), to: fileURL)
    }

    func clear() {
        sessions = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Everything a bug report needs, one session per line, newest first.
    var report: String {
        let header = "JustScribe \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") "
            + "(\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?")), "
            + "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        return ([header] + sessions.map(\.line)).joined(separator: "\n")
    }
}

nonisolated struct DiagnosticsFile: Codable, Equatable, Sendable {
    static let currentVersion = 1
    var version: Int
    var sessions: [SessionDiagnostic]
}
