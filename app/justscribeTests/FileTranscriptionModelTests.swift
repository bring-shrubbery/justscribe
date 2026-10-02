//
//  FileTranscriptionModelTests.swift
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
struct FileTranscriptionModelTests {

    @Test func speakersOffMeansNoSpeakerPass() {
        #expect(FileTranscriptionModel.speakerRequest(identify: false, countText: "3") == .none)
    }

    @Test func anEmptyCountMeansDetect() {
        #expect(FileTranscriptionModel.speakerRequest(identify: true, countText: "") == .detect)
        #expect(FileTranscriptionModel.speakerRequest(identify: true, countText: "  ") == .detect)
    }

    @Test func aCountFromOneToTenIsExact() {
        #expect(FileTranscriptionModel.speakerRequest(identify: true, countText: "1") == .exactly(1))
        #expect(FileTranscriptionModel.speakerRequest(identify: true, countText: " 10 ") == .exactly(10))
    }

    @Test func anythingElseFallsBackToDetect() {
        for text in ["0", "11", "-2", "two", "2.5"] {
            #expect(FileTranscriptionModel.speakerRequest(identify: true, countText: text) == .detect)
        }
    }

    @Test func theSaveNameReplacesTheExtension() {
        #expect(FileTranscriptionModel.saveName(for: URL(fileURLWithPath: "/a/b/interview.final.m4a")) == "interview.final.txt")
        #expect(FileTranscriptionModel.saveName(for: URL(fileURLWithPath: "/a/recording")) == "recording.txt")
    }

    // MARK: - Status line

    private func status(
        _ phase: FileTranscriptionJob.Phase, cancelling: Bool = false, durationKnown: Bool = true
    ) -> FileTranscriptionModel.Status {
        FileTranscriptionModel.status(phase: phase, isCancelling: cancelling, isDurationKnown: durationKnown)
    }

    @Test func openingIsIndeterminate() {
        #expect(status(.idle, durationKnown: false) == .working("Opening…", progress: nil))
    }

    @Test func identifyingSpeakersIsIndeterminate() {
        #expect(status(.identifyingSpeakers) == .working("Identifying speakers…", progress: nil))
    }

    @Test func transcribingShowsAPercentageWhenTheDurationIsKnown() {
        #expect(status(.transcribing(0.427)) == .working("Transcribing… 42%", progress: 0.427))
    }

    @Test func transcribingIsIndeterminateWhenTheDurationIsUnknown() {
        #expect(status(.transcribing(0), durationKnown: false) == .working("Transcribing…", progress: nil))
    }

    @Test func pausedKeepsItsProgressOnlyWhenTheDurationIsKnown() {
        #expect(status(.pausedForDictation(0.5)) == .working("Paused while you dictate", progress: 0.5))
        #expect(status(.pausedForDictation(0), durationKnown: false) == .working("Paused while you dictate", progress: nil))
    }

    @Test func aPendingCancelSaysStoppingWhateverThePhase() {
        for phase: FileTranscriptionJob.Phase in [.idle, .identifyingSpeakers, .transcribing(0.3), .pausedForDictation(0.3)] {
            #expect(status(phase, cancelling: true) == .working("Stopping…", progress: nil))
        }
    }

    @Test func finalPhasesEnd() {
        #expect(status(.finished) == .ended("Done", systemImage: "checkmark.circle.fill"))
        #expect(status(.cancelled) == .ended("Cancelled", systemImage: "xmark.circle"))
        #expect(status(.failed(FileTranscriptionJob.Message.noSpeech))
            == .ended(FileTranscriptionJob.Message.noSpeech, systemImage: "exclamationmark.triangle.fill"))
    }
}
