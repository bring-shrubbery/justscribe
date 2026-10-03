//
//  HistoryPolicyTests.swift
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

@Suite(.timeLimit(.minutes(1)))
struct HistoryPolicyTests {

    @Test func nothingIsKeptWhenBothSwitchesAreOff() {
        let keep = HistoryPolicy.shouldKeep(text: "Hello", keepTranscriptions: false, keepAudio: false)
        #expect(keep.text == false && keep.audio == false)
    }

    @Test func audioAloneKeepsNothing() {
        let keep = HistoryPolicy.shouldKeep(text: "Hello", keepTranscriptions: false, keepAudio: true)
        #expect(keep.text == false && keep.audio == false)
    }

    @Test func textIsKeptWithoutAudio() {
        let keep = HistoryPolicy.shouldKeep(text: "Hello", keepTranscriptions: true, keepAudio: false)
        #expect(keep.text == true && keep.audio == false)
    }

    @Test func bothAreKeptWhenBothAreOn() {
        let keep = HistoryPolicy.shouldKeep(text: "Hello", keepTranscriptions: true, keepAudio: true)
        #expect(keep.text == true && keep.audio == true)
    }

    @Test func blankTextKeepsNothingEvenWithBothOn() {
        for text in ["", "   ", "\n\t"] {
            let keep = HistoryPolicy.shouldKeep(text: text, keepTranscriptions: true, keepAudio: true)
            #expect(keep.text == false && keep.audio == false)
        }
    }

    @Test func rowTitleIsTheFirstNonEmptyLineTrimmed() {
        #expect(HistoryPolicy.rowTitle("  \n\n  Dear Sam,  \nSecond line") == "Dear Sam,")
        #expect(HistoryPolicy.rowTitle("one line") == "one line")
        #expect(HistoryPolicy.rowTitle("   ") == "")
    }

    @Test func rowTimeSaysTodayYesterdayOrTheDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_GB")
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 15, minute: 30))!
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 14, minute: 5))!
        let yesterdayLate = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 23, minute: 59))!
        let older = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 9, minute: 12))!
        #expect(HistoryPolicy.rowTime(today, now: now, calendar: calendar) == "Today 14:05")
        #expect(HistoryPolicy.rowTime(yesterdayLate, now: now, calendar: calendar) == "Yesterday 23:59")
        #expect(HistoryPolicy.rowTime(older, now: now, calendar: calendar) == "28 Sep 2026 09:12")
    }

    @Test func durationIsMinutesAndSeconds() {
        #expect(HistoryPolicy.duration(0) == "0:00")
        #expect(HistoryPolicy.duration(42.7) == "0:42")
        #expect(HistoryPolicy.duration(61) == "1:01")
        #expect(HistoryPolicy.duration(3725) == "62:05")
    }

    @Test func recordsRoundTripThroughJSON() throws {
        let record = DictationRecord(
            id: UUID(), createdAt: Date(timeIntervalSince1970: 1_790_000_000), text: "Hi",
            durationSeconds: 3.5, modelID: "fluidaudio:v3", language: "en", audioFileName: "a.m4a")
        let index = HistoryIndex(version: 1, records: [record])
        let data = try JSONEncoder().encode(index)
        #expect(try JSONDecoder().decode(HistoryIndex.self, from: data) == index)
    }
}
