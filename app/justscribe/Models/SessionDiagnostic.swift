//
//  SessionDiagnostic.swift
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

/// One dictation session's facts, kept so a user can report what went wrong without a debugger:
/// what was captured, what the model returned, and how the session ended.
nonisolated struct SessionDiagnostic: Codable, Equatable, Sendable {
    var startedAt: Date
    var trigger: String
    var insertionMode: String
    var modelID: String
    var microphone: String
    /// The device's format as the capture delegate saw it.
    var inputSampleRate: Double
    var channels: Int
    /// Samples handed to the model (16 kHz) and their RMS level (0 = silence).
    var samples: Int
    var rms: Float
    var streamedCharacters: Int
    var finalCharacters: Int
    var finalPassMilliseconds: Int
    var insertedCharacters: Int
    /// How the session ended, in the overlay's words.
    var outcome: String

    var seconds: Double { Double(samples) / 16_000 }

    /// One line for the report.
    var line: String {
        let time = Self.timeFormatter.string(from: startedAt)
        return "\(time) \(trigger)/\(insertionMode) \(modelID) mic=\(microphone) \(Int(inputSampleRate))Hz×\(channels) "
            + "audio=\(String(format: "%.1f", seconds))s rms=\(String(format: "%.4f", rms)) "
            + "streamed=\(streamedCharacters) final=\(finalCharacters) (\(finalPassMilliseconds)ms) inserted=\(insertedCharacters) → \(outcome)"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// The RMS of a sample buffer; 0 for an empty one.
    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return (sum / Float(samples.count)).squareRoot()
    }
}
