//
//  HistoryPolicy.swift
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

/// The rules of history that need no store: what to keep, and how a record reads in a row.
nonisolated enum HistoryPolicy {
    /// Text is kept when the switch is on and there is text; audio only alongside text.
    static func shouldKeep(text: String, keepTranscriptions: Bool, keepAudio: Bool) -> (text: Bool, audio: Bool) {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let keepText = keepTranscriptions && hasText
        return (keepText, keepText && keepAudio)
    }

    /// The first non-empty line, trimmed; empty when there is none.
    static func rowTitle(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
    }

    /// "Today 14:05", "Yesterday 09:12", else "28 Sep 2026 09:12".
    static func rowTime(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = DateFormatter()
        time.calendar = calendar
        time.locale = calendar.locale
        time.timeZone = calendar.timeZone
        time.dateFormat = "HH:mm"
        if calendar.isDate(date, inSameDayAs: now) { return "Today \(time.string(from: date))" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday \(time.string(from: date))"
        }
        let day = DateFormatter()
        day.calendar = calendar
        day.locale = calendar.locale
        day.timeZone = calendar.timeZone
        day.dateFormat = "d MMM yyyy HH:mm"
        return day.string(from: date)
    }

    /// `3725` → `62:05`.
    static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
