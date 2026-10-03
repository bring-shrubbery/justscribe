//
//  VoiceCommandProcessorTests.swift
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

@Suite(.timeLimit(.minutes(1)))
struct VoiceCommandProcessorTests {

    private func run(_ text: String, commands: Bool = true, punctuation: Bool = false, session: Bool = true) -> (text: String, actions: [DictationAction]) {
        VoiceCommandProcessor.apply(text, commandsOn: commands, punctuationOn: punctuation, sessionCommandsOn: session)
    }

    @Test func newLineAndNewParagraphAtSentenceBoundaries() {
        #expect(run("First point. New line. Second point").text == "First point.\nSecond point")
        #expect(run("Dear Sam, new paragraph, thanks for the file").text == "Dear Sam,\n\nthanks for the file")
        #expect(run("Done new paragraph").text == "Done\n\n")   // a final line break is kept (fix round 1 ruling)
    }

    @Test func aCommandInsideAClauseIsLeftAlone() {
        #expect(run("add a new line in the budget").text == "add a new line in the budget")
        #expect(run("I will send it later").text == "I will send it later")
    }

    @Test func scratchThatRemovesToThePreviousBreak() {
        #expect(run("Buy milk. Buy eggs scratch that").text == "Buy milk.")
        #expect(run("Buy milk. Buy eggs. Delete that. Buy bread").text == "Buy milk. Buy bread")
        #expect(run("First. New line. Wrong words scratch that right words").text == "First.\nright words")
    }

    @Test func scratchThatTwiceAndWithNothingBefore() {
        #expect(run("One. Two scratch that scratch that").text == "")
        #expect(run("scratch that").text == "")
        #expect(run("").text == "")
    }

    @Test func stopRecordingEndsTheSessionOnlyInPressMode() {
        let press = run("Call me tomorrow. Stop recording")
        #expect(press.text == "Call me tomorrow.")
        #expect(press.actions == [.stopRecording])
        let hold = run("Call me tomorrow. Stop recording", session: false)
        #expect(hold.text == "Call me tomorrow.")
        #expect(hold.actions.isEmpty)
    }

    @Test func sendNeedsASentenceEndBeforeItAndTheEndAfterIt() {
        let sent = run("Thanks. Send")
        #expect(sent.text == "Thanks.")
        #expect(sent.actions == [.stopRecording, .pressReturn])
        #expect(run("Thanks, press enter").actions == [.stopRecording, .pressReturn])
        #expect(run("I'll send").text == "I'll send")
        #expect(run("Send it. Thanks").text == "Send it. Thanks")
        #expect(run("Thanks. Send", session: false).text == "Thanks.")
        #expect(run("Thanks. Send", session: false).actions.isEmpty)
    }

    @Test func spokenPunctuationOnlyWhenOn() {
        #expect(run("Hello comma world period", punctuation: true).text == "Hello, world.")
        #expect(run("Hello comma world period").text == "Hello comma world period")
        #expect(run("She said open quote yes close quote and left", punctuation: true).text == "She said \"yes\" and left")
        #expect(run("Why question mark", punctuation: true).text == "Why?")
        #expect(run("period", punctuation: true).text == "")
    }

    @Test func everythingOffLeavesTheTextAlone() {
        let out = run("Done. New line. Stop recording", commands: false)
        #expect(out.text == "Done. New line. Stop recording")
        #expect(out.actions.isEmpty)
    }

    @Test func noDoubleSpacesRemain() {
        #expect(run("a scratch that b").text == "b")
        #expect(run("a. new line b").text == "a.\nb")
        #expect(!run("x. New line. y. New paragraph. z").text.contains("  "))
    }

    @Test func terminatingCommandAtTheEndOfStreamedText() {
        #expect(VoiceCommandProcessor.terminatingCommand(in: "Call me tomorrow. Stop recording", sessionCommandsOn: true) == .stopRecording)
        #expect(VoiceCommandProcessor.terminatingCommand(in: "Call me tomorrow stop recording", sessionCommandsOn: true) == .stopRecording)
        #expect(VoiceCommandProcessor.terminatingCommand(in: "Thanks. Send", sessionCommandsOn: true) == .pressReturn)
        #expect(VoiceCommandProcessor.terminatingCommand(in: "I'll send", sessionCommandsOn: true) == nil)
        #expect(VoiceCommandProcessor.terminatingCommand(in: "Stop recording the show", sessionCommandsOn: true) == nil)
        #expect(VoiceCommandProcessor.terminatingCommand(in: "Thanks. Stop recording", sessionCommandsOn: false) == nil)
    }

    @Test func deleteThatStandsAloneButScratchThatFiresAnywhere() {
        #expect(run("Can you delete that email. Thanks").text == "Can you delete that email. Thanks")
        #expect(run("wrong words scratch that right words").text == "right words")
        #expect(run("Buy eggs. Delete that").text == "")
    }

    @Test func aLineBreakSpokenAtTheEndIsKept() {
        #expect(run("Hello. New line").text == "Hello.\n")
        #expect(run("Dear Sam, new paragraph").text == "Dear Sam,\n\n")
    }

    @Test func aClosingQuoteDoesNotHideASentenceEnd() {
        #expect(run("He said \"yes.\" Then wrong scratch that").text == "He said \"yes.\"")
    }

    @Test func terminatingCommandIgnoresPunctuationInsideThePhrase() {
        #expect(VoiceCommandProcessor.terminatingCommand(in: "I will stop. Recording", sessionCommandsOn: true) == nil)
    }

    @Test func repeatedSessionCommandsAskOnce() {
        #expect(run("stop recording stop recording").actions == [.stopRecording])
        #expect(run("Thanks. Send").actions == [.stopRecording, .pressReturn])
    }
}
