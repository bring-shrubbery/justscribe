//
//  ShortRecording.swift
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

/// What to do with a dictation that ended almost as soon as it began.
nonisolated enum ShortRecording: Equatable {
    /// A tap on the shortcut with nothing heard: the indicator just goes away, with no error.
    case dismissQuietly
    /// Too short for the model, but something was heard: say so.
    case tooShort
    /// Long enough to transcribe.
    case transcribe

    /// Under this, a recording with nothing in it is treated as a tap by mistake.
    static let quietLimit: TimeInterval = 1.0
    /// Under this, the model is not asked.
    static let minimumDuration: TimeInterval = 0.3

    static func outcome(duration: TimeInterval, isSilent: Bool) -> ShortRecording {
        if duration < quietLimit, isSilent { return .dismissQuietly }
        return duration < minimumDuration ? .tooShort : .transcribe
    }
}
