//
//  LiveAudioMixerTests.swift
//  justscribeTests
//
//  Created by Antoni Silvestrovic on 24/01/2026.
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

struct LiveAudioMixerTests {
    @Test func oneSourcePassesStraightThrough() {
        var mixer = LiveAudioMixer(kinds: [.microphone])
        #expect(mixer.append([0.1, 0.2], from: .microphone) == [0.1, 0.2])
        #expect(mixer.finish().isEmpty)
    }

    @Test func twoSourcesAreSummedSampleBySample() {
        var mixer = LiveAudioMixer(kinds: [.microphone, .systemAudio])
        #expect(mixer.append([0.25, 0.25, 0.25], from: .microphone).isEmpty)
        #expect(mixer.append([0.5, 0.5], from: .systemAudio) == [0.75, 0.75])
        // The microphone's third sample waits for the system audio's.
        #expect(mixer.append([0.5], from: .systemAudio) == [0.75])
    }

    @Test func theMixIsClippedToFullScale() {
        var mixer = LiveAudioMixer(kinds: [.microphone, .systemAudio])
        _ = mixer.append([0.8, -0.8], from: .microphone)
        #expect(mixer.append([0.8, -0.8], from: .systemAudio) == [1, -1])
    }

    @Test func aStalledSourceIsPaddedWithSilenceOnceItLagsTooFar() {
        var mixer = LiveAudioMixer(kinds: [.microphone, .systemAudio])
        let lag = LiveAudioMixer.maximumLag
        // Up to the allowed lag, the mix waits.
        #expect(mixer.append([Float](repeating: 0.5, count: lag), from: .microphone).isEmpty)
        // Beyond it, the silent source is padded and the excess comes out.
        let out = mixer.append([Float](repeating: 0.5, count: 100), from: .microphone)
        #expect(out.count == 100)
        #expect(out.allSatisfy { $0 == 0.5 })
    }

    @Test func finishingPadsTheShorterSource() {
        var mixer = LiveAudioMixer(kinds: [.microphone, .systemAudio])
        _ = mixer.append([0.25, 0.25, 0.25], from: .microphone)
        _ = mixer.append([0.5], from: .systemAudio)
        #expect(mixer.finish() == [0.25, 0.25])
        #expect(mixer.finish().isEmpty)
    }
}
