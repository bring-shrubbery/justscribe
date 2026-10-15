//
//  ShortRecordingTests.swift
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

import Testing
@testable import justscribe

struct ShortRecordingTests {
    @Test func aTapWithNothingHeardIsDismissedWithoutAnError() {
        #expect(ShortRecording.outcome(duration: 0.1, isSilent: true) == .dismissQuietly)
        #expect(ShortRecording.outcome(duration: 0.6, isSilent: true) == .dismissQuietly)
        #expect(ShortRecording.outcome(duration: 0.99, isSilent: true) == .dismissQuietly)
    }

    @Test func aTooShortRecordingWithSoundSaysSo() {
        #expect(ShortRecording.outcome(duration: 0.1, isSilent: false) == .tooShort)
        #expect(ShortRecording.outcome(duration: 0.29, isSilent: false) == .tooShort)
    }

    @Test func anythingLongEnoughIsTranscribedEvenWhenSilent() {
        #expect(ShortRecording.outcome(duration: 0.3, isSilent: false) == .transcribe)
        #expect(ShortRecording.outcome(duration: 1.0, isSilent: true) == .transcribe)
        #expect(ShortRecording.outcome(duration: 5, isSilent: false) == .transcribe)
    }
}
