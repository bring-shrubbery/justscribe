//
//  DiagnosticsLogTests.swift
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

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct DiagnosticsLogTests {

    private func tempFile() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("justscribe-diag-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("diagnostics.json")
    }

    private func session(_ i: Int, outcome: String = "Done") -> SessionDiagnostic {
        SessionDiagnostic(startedAt: Date(timeIntervalSince1970: Double(1_790_000_000 + i)), trigger: "hold", insertionMode: "paste",
                          modelID: "fluidaudio:v3", microphone: "MacBook Pro Microphone", inputSampleRate: 48_000, channels: 1,
                          samples: 32_000 * i, rms: 0.05, streamedCharacters: 10, finalCharacters: 12, finalPassMilliseconds: 340,
                          insertedCharacters: 12, outcome: outcome)
    }

    @Test func recordsNewestFirstAndKeepsTwenty() throws {
        let url = try tempFile(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let log = DiagnosticsLog(fileURL: url); log.load()
        for i in 1...25 { log.record(session(i)) }
        #expect(log.sessions.count == 20)
        #expect(log.sessions.first?.samples == 32_000 * 25)
        let again = DiagnosticsLog(fileURL: url); again.load()
        #expect(again.sessions == log.sessions)
    }

    @Test func clearEmptiesMemoryAndDisk() throws {
        let url = try tempFile(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let log = DiagnosticsLog(fileURL: url); log.load()
        log.record(session(1)); log.clear()
        #expect(log.sessions.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func theReportHasAHeaderAndOneLinePerSession() throws {
        let url = try tempFile(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let log = DiagnosticsLog(fileURL: url); log.load()
        log.record(session(1, outcome: "No speech detected"))
        let lines = log.report.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("JustScribe "))
        #expect(lines[1].contains("audio=2.0s") && lines[1].contains("48000Hz×1") && lines[1].contains("→ No speech detected"))
    }

    @Test func rmsIsZeroForSilenceAndEmpty() {
        #expect(SessionDiagnostic.rms([]) == 0)
        #expect(SessionDiagnostic.rms([0, 0, 0]) == 0)
        #expect(abs(SessionDiagnostic.rms([0.5, -0.5, 0.5, -0.5]) - 0.5) < 0.0001)
    }
}
