//
//  RecordingTrigger.swift
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

/// How the shortcut drives a recording.
nonisolated enum RecordingTrigger: String, Codable, CaseIterable, Sendable {
    /// Hold the shortcut; release to finish (the default).
    case hold
    /// Press once to start, again to stop.
    case pressToToggle = "toggle"

    static let defaultTrigger = RecordingTrigger.hold

    static func stored(_ rawValue: String?) -> RecordingTrigger {
        rawValue.flatMap(RecordingTrigger.init(rawValue:)) ?? defaultTrigger
    }

    var title: String {
        switch self {
        case .hold: "Hold to record"
        case .pressToToggle: "Press to start, press again to stop"
        }
    }

    var detail: String {
        switch self {
        case .hold: "Recording lasts as long as the shortcut is held."
        case .pressToToggle: "Say \"stop recording\" or press the shortcut again to finish. A recording stops by itself after 10 minutes. Modifier-only shortcuts need to be held for a moment."
        }
    }
}
