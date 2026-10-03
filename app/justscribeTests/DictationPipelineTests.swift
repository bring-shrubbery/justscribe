//
//  DictationPipelineTests.swift
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
struct DictationPipelineTests {

    private final class FakeCleanUp {
        var calls: [(text: String, instructions: String)] = []
        var result: String? = nil      // nil → echo upper-cased
        var error: Error? = nil
        func run(_ text: String, _ instructions: String, _ language: String?) async throws -> String {
            calls.append((text, instructions))
            if let error { throw error }
            return result ?? text.uppercased()
        }
    }
    private struct Boom: Error {}

    private func context(cleanUp: Bool = true, modeCleanUp: Bool = true, press: Bool = true, commands: Bool = true, punctuation: Bool = false, vocabulary: [VocabularyEntry] = []) -> DictationContext {
        var mode = DictationMode.makeDefault()
        mode.cleanUp = modeCleanUp
        mode.instructions = "Be brief."
        return DictationContext(voiceCommands: commands, spokenPunctuation: punctuation, pressToToggle: press,
                                vocabulary: vocabulary, mode: mode, cleanUpEnabled: cleanUp, language: "en")
    }

    @Test func stagesRunInOrderCommandsVocabularyCleanUp() async {
        let fake = FakeCleanUp()
        let pipeline = DictationPipeline(cleanUp: fake.run, isDictionaryWord: { _ in false })
        let vocab = [VocabularyEntry(id: UUID(), text: "Quassum", heardAs: ["quasum"], createdAt: Date())]
        let result = await pipeline.process("Hello quasum. New line. Bye", context: context(vocabulary: vocab))
        #expect(fake.calls.count == 1)
        #expect(fake.calls[0].text == "Hello Quassum.\nBye")
        #expect(fake.calls[0].instructions == "Be brief.")
        #expect(result.text == "HELLO QUASSUM.\nBYE")
        #expect(result.actions.isEmpty)
    }

    @Test func cleanUpIsSkippedWhenTheGlobalSwitchOrTheModeSaysSo() async {
        let fake = FakeCleanUp()
        let pipeline = DictationPipeline(cleanUp: fake.run, isDictionaryWord: { _ in true })
        let a = await pipeline.process("hello", context: context(cleanUp: false))
        let b = await pipeline.process("hello", context: context(modeCleanUp: false))
        #expect(a.text == "hello" && b.text == "hello")
        #expect(fake.calls.isEmpty)
    }

    @Test func aFailedOrEmptyCleanUpKeepsTheText() async {
        let failing = FakeCleanUp(); failing.error = Boom()
        let p1 = DictationPipeline(cleanUp: failing.run, isDictionaryWord: { _ in true })
        #expect(await p1.process("keep me", context: context()).text == "keep me")
        let empty = FakeCleanUp(); empty.result = "   "
        let p2 = DictationPipeline(cleanUp: empty.run, isDictionaryWord: { _ in true })
        #expect(await p2.process("keep me", context: context()).text == "keep me")
    }

    @Test func actionsPassThroughAndNothingIsCleanedWhenEmpty() async {
        let fake = FakeCleanUp()
        let pipeline = DictationPipeline(cleanUp: fake.run, isDictionaryWord: { _ in true })
        let result = await pipeline.process("Thanks. Send", context: context())
        #expect(result.text == "THANKS.")
        #expect(result.actions == [.stopRecording, .pressReturn])
        let blank = await pipeline.process("scratch that", context: context())
        #expect(blank.text == "")
        #expect(fake.calls.count == 1)   // only the first call reached clean-up
    }

    @Test func holdModeDropsSessionCommandsWithoutActions() async {
        let pipeline = DictationPipeline(cleanUp: { t, _, _ in t }, isDictionaryWord: { _ in true })
        let result = await pipeline.process("Done. Stop recording", context: context(press: false))
        #expect(result.text == "Done.")
        #expect(result.actions.isEmpty)
    }

    @Test func terminatingCommandRespectsTheTrigger() {
        #expect(DictationPipeline.terminatingCommand(in: "ok stop recording", context: context()) == .stopRecording)
        #expect(DictationPipeline.terminatingCommand(in: "ok stop recording", context: context(press: false)) == nil)
        #expect(DictationPipeline.terminatingCommand(in: "ok stop recording", context: context(commands: false)) == nil)
    }

    @Test func aTrailingLineBreakSurvivesATrimmingCleanUp() async {
        let pipeline = DictationPipeline(
            cleanUp: { t, _, _ in t.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) },
            isDictionaryWord: { _ in true })
        let result = await pipeline.process("Hello. New line", context: context())
        #expect(result.text == "HELLO.\n")
    }
}
