# Vocabulary, Toggle Recording, Voice Commands and Modes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dictation that fits its user: a vocabulary of words to spell right, a shortcut that can be pressed instead of held, spoken commands for layout and corrections, and clean-up instructions chosen by the app in front.

**Architecture:** One pure, tested `DictationPipeline` (voice commands → vocabulary → clean-up with the mode's instructions) replaces the grammar-correction call in `AppDelegate.stopRecordingAndFinalize`; insertion bookkeeping is untouched. Vocabulary and modes are JSON files in the container with `@Observable` stores, like History. The two grammar backends take instructions per request. `AppDelegate` gains a press-to-toggle trigger with a safety stop.

**Tech Stack:** Swift (language mode 5, default actor isolation MainActor, approachable concurrency), SwiftUI + AppKit, WhisperKit (`DecodingOptions.promptTokens`), FoundationModels, MLXLMCommon `ChatSession`, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-03-dictation-quality-design.md`

## Global Constraints

- Branch `dictation-quality`. Never commit to `main`, never push: every code commit on `main` is released to users.
- Commit after each task with a user-readable subject (subjects become release notes; prefix `docs:`/`ci:` for changes users never see) and end the message with a `Co-Authored-By:` trailer naming the model that did the work.
- Build: `xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -configuration Debug build`. Unit tests: `xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests` (one type: append `/<TypeName>`). The app target must build and every unit test pass at the end of every task. Builds take minutes; trust only `xcodebuild`, never SourceKit diagnostics.
- New files under `app/justscribe/` and `app/justscribeTests/` are picked up automatically; never edit `project.pbxproj`; never stage `xcuserdata/`.
- Default actor isolation is **MainActor** with `SWIFT_APPROACHABLE_CONCURRENCY`: pure value types and helpers are declared `nonisolated`; a nonisolated async function runs on its caller's actor unless `@concurrent`.
- Tests run inside the app and share its bundle ID: **no test writes `UserDefaults.standard` or touches the app's real files.** Stores in tests use `FileManager.default.temporaryDirectory` subfolders they create and remove. **Never open an `AVAssetReader` in a new test** (a third concurrent one deadlocks the CI runner).
- Do not launch the app from a subagent.
- Every new Swift file starts with the project's GPL-3.0 header (copy it from `app/justscribe/Services/History/HistoryPolicy.swift`), with its own file name on line 2 and `justscribe` / `justscribeTests` on line 3.
- Exact values: UserDefaults keys `recordingTrigger` (`hold` | `toggle`, default `hold`), `voiceCommandsEnabled` (default `true`), `spokenPunctuationEnabled` (default `false`); `grammarCorrectionEnabled` keeps its name as the global Clean-up switch. Files `Application Support/<bundle id>/vocabulary.json` and `modes.json`, ISO 8601 dates, atomic writes, damaged file renamed `<name>.broken`. Default mode UUID `00000000-0000-0000-0000-000000000001`, name "Default", instructions "Fix grammar, spelling and punctuation. Preserve the meaning and tone." Whisper prompt cap 200 tokens. Safety stop 10 minutes. Edit-distance bound 1 for keys of ≤ 5 letters, else 2. Commands table and stand-alone rule exactly as in Task 1's tests.
- The frame around a mode's instructions: `"<instructions>\n\nApply this to the text that follows. Output only the resulting text: no explanations, no quotes, no preamble."`

## Review Focus

1. **"send" at the end of an ordinary sentence** ("I'll send") must not fire; "Thanks. Send" must. Pinned in Task 1.
2. **"scratch that" twice, and with nothing before it** — removes to the previous break each time; never crashes on an empty text. Pinned in Task 1.
3. **A dictionary word that sounds like a vocabulary entry** ("mark" vs "Marc") stays; a non-word mishearing ("quasum") is fixed; the result is idempotent. Pinned in Task 2.
4. **Settings change mid-dictation** — the trigger, mode and app are read at key-down and kept for the session; a press-mode session started before switching to hold still stops on the next press. Pinned by the `sessionTrigger` field in Task 7 and the hand checks.
5. **Clean-up off for a mode while the global switch is on** (a Terminal mode) must skip the model entirely, and vice versa. Pinned in Task 4.

---

### Task 1: Voice commands

**Files:**
- Create: `app/justscribe/Services/Dictation/VoiceCommandProcessor.swift`, `app/justscribe/Models/DictationAction.swift`
- Test: `app/justscribeTests/VoiceCommandProcessorTests.swift`

**Interfaces:**
- Produces: `nonisolated enum DictationAction: Equatable, Sendable { case stopRecording, pressReturn }`; `VoiceCommandProcessor.apply(_ text: String, commandsOn: Bool, punctuationOn: Bool, sessionCommandsOn: Bool) -> (text: String, actions: [DictationAction])`; `VoiceCommandProcessor.terminatingCommand(in: String, sessionCommandsOn: Bool) -> DictationAction?`.

- [ ] **Step 1: Write the failing tests**

```swift
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
        #expect(run("Done new paragraph").text == "Done")
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
}
```

- [ ] **Step 2: Run; it must fail to compile**

Run: `xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests/VoiceCommandProcessorTests 2>&1 | grep -E "error:|\*\* TEST" | head`
Expected: `error: cannot find 'VoiceCommandProcessor' in scope`

- [ ] **Step 3: Write `DictationAction.swift`**

```swift
import Foundation

/// What a dictation asks the app to do besides inserting text, from a spoken command.
nonisolated enum DictationAction: Equatable, Sendable {
    /// End the session now (press-to-toggle mode).
    case stopRecording
    /// After the text is inserted, press Return.
    case pressReturn
}
```

- [ ] **Step 4: Write `VoiceCommandProcessor.swift`**

```swift
import Foundation

/// Spoken commands in a transcript: layout ("new line"), editing ("scratch that"), session
/// ("stop recording", "send") and, when turned on, punctuation words. Pure; English phrases.
nonisolated enum VoiceCommandProcessor {

    private enum Command: Equatable {
        case newLine, newParagraph, scratch, stop, send
        case punctuation(String, glue: Glue)
    }
    private enum Glue: Equatable { case previous, next }

    private static let layoutAndEditing: [([String], Command)] = [
        (["new", "paragraph"], .newParagraph),
        (["new", "line"], .newLine),
        (["scratch", "that"], .scratch),
        (["delete", "that"], .scratch),
    ]
    private static let session: [([String], Command)] = [
        (["stop", "recording"], .stop),
        (["stop", "dictation"], .stop),
        (["press", "enter"], .send),
        (["send"], .send),
    ]
    private static let punctuation: [([String], Command)] = [
        (["full", "stop"], .punctuation(".", glue: .previous)),
        (["period"], .punctuation(".", glue: .previous)),
        (["comma"], .punctuation(",", glue: .previous)),
        (["question", "mark"], .punctuation("?", glue: .previous)),
        (["exclamation", "mark"], .punctuation("!", glue: .previous)),
        (["exclamation", "point"], .punctuation("!", glue: .previous)),
        (["colon"], .punctuation(":", glue: .previous)),
        (["semicolon"], .punctuation(";", glue: .previous)),
        (["open", "quote"], .punctuation("\"", glue: .next)),
        (["close", "quote"], .punctuation("\"", glue: .previous)),
        (["dash"], .punctuation("—", glue: .previous)),
    ]

    /// A whitespace-separated token: the word with the punctuation the model put around it.
    private struct Token {
        var leading: String
        var core: String
        var trailing: String
        var lowercased: String { core.lowercased() }
        var endsSentence: Bool { trailing.contains(where: { ".?!".contains($0) }) }
        var endsClause: Bool { trailing.contains(where: { ".?!,;:".contains($0) }) }
        var text: String { leading + core + trailing }
    }

    private static func tokens(_ text: String) -> [Token] {
        text.split(whereSeparator: \.isWhitespace).map { piece in
            let s = String(piece)
            let coreStart = s.firstIndex(where: { $0.isLetter || $0.isNumber }) ?? s.endIndex
            let coreEnd = s.lastIndex(where: { $0.isLetter || $0.isNumber }).map { s.index(after: $0) } ?? coreStart
            return Token(leading: String(s[..<coreStart]), core: String(s[coreStart..<coreEnd]), trailing: String(s[coreEnd...]))
        }
    }

    /// Applies the commands and returns the text with them removed, plus the actions they asked for.
    static func apply(_ text: String, commandsOn: Bool, punctuationOn: Bool, sessionCommandsOn: Bool) -> (text: String, actions: [DictationAction]) {
        guard commandsOn else { return (text, []) }
        let all = tokens(text)
        var table = layoutAndEditing + session
        if punctuationOn { table += punctuation }
        table.sort { $0.0.count > $1.0.count }   // longest phrase first

        var out: [Piece] = []
        var lastCommandEnd = 0        // index in `out` just after the last command's effect
        var pendingPrefix = ""        // an open quote waiting for the next word
        var actions: [DictationAction] = []
        var i = 0
        while i < all.count {
            if let (phrase, command) = match(at: i, in: all, table: table) {
                let end = i + phrase.count
                let precededByBreak = i == 0 || all[i - 1].endsClause
                let followedByBreak = end == all.count || all[end - 1].endsClause
                let standsAlone = precededByBreak || followedByBreak
                let qualifies: Bool
                switch command {
                case .send: qualifies = precededByBreak && end == all.count
                case .punctuation: qualifies = true      // punctuation words live mid-sentence by nature
                default: qualifies = standsAlone
                }
                if qualifies {
                    switch command {
                    case .newLine:
                        out.append(.lineBreak("\n")); lastCommandEnd = out.count
                    case .newParagraph:
                        out.append(.lineBreak("\n\n")); lastCommandEnd = out.count
                    case .scratch:
                        // The sentence end right before the command is the pause before it, not a break
                        // to keep; with nothing new since the last command, remove the previous sentence.
                        var breakAt = max(lastCommandEnd, indexAfterLastSentenceEnd(out, ignoringLast: true))
                        if breakAt >= out.count { breakAt = indexAfterLastSentenceEnd(out, ignoringLast: true) }
                        out.removeSubrange(min(breakAt, out.count)...)
                        lastCommandEnd = out.count
                    case .stop:
                        if sessionCommandsOn { actions.append(.stopRecording) }
                        lastCommandEnd = out.count
                    case .send:
                        if sessionCommandsOn { actions.append(.stopRecording); actions.append(.pressReturn) }
                        lastCommandEnd = out.count
                    case .punctuation(let mark, let glue):
                        switch glue {
                        case .previous:
                            if let last = out.indices.last, case .word(let w) = out[last] { out[last] = .word(w + mark) }
                        case .next:
                            pendingPrefix += mark
                        }
                    }
                    i = end
                    continue
                }
            }
            let token = all[i]
            out.append(.word(pendingPrefix + token.text))
            pendingPrefix = ""
            i += 1
        }
        return (render(out), actions)
    }

    /// The session command the streamed text ends with, if any — read live while recording.
    static func terminatingCommand(in streamed: String, sessionCommandsOn: Bool) -> DictationAction? {
        guard sessionCommandsOn else { return nil }
        let all = tokens(streamed)
        for (phrase, command) in session where all.count >= phrase.count {
            let start = all.count - phrase.count
            guard matches(phrase, at: start, in: all) else { continue }
            let precededByBreak = start == 0 || all[start - 1].endsClause
            switch command {
            case .stop: return .stopRecording
            case .send: return precededByBreak ? .pressReturn : nil
            default: continue
            }
        }
        return nil
    }

    // MARK: - Pieces

    private enum Piece { case word(String), lineBreak(String) }

    private static func match(at i: Int, in all: [Token], table: [([String], Command)]) -> ([String], Command)? {
        for (phrase, command) in table where matches(phrase, at: i, in: all) {
            // Only the phrase's last word may carry punctuation; "new. line" is two words, not a command.
            let inner = all[i..<(i + phrase.count - 1)]
            if inner.contains(where: { !$0.trailing.isEmpty }) { continue }
            return (phrase, command)
        }
        return nil
    }

    private static func matches(_ phrase: [String], at i: Int, in all: [Token]) -> Bool {
        guard i + phrase.count <= all.count else { return false }
        for (offset, word) in phrase.enumerated() where all[i + offset].lowercased != word { return false }
        return true
    }

    /// The position after the last sentence end in `out`; with `ignoringLast`, the final piece's own
    /// punctuation does not count (it is the boundary the command sits on).
    private static func indexAfterLastSentenceEnd(_ out: [Piece], ignoringLast: Bool) -> Int {
        let last = ignoringLast ? out.count - 2 : out.count - 1
        guard last >= 0 else { return 0 }
        for index in stride(from: last, through: 0, by: -1) {
            if case .word(let w) = out[index], let c = w.last, ".?!".contains(c) { return index + 1 }
        }
        return 0
    }

    private static func render(_ pieces: [Piece]) -> String {
        var result = ""
        for piece in pieces {
            switch piece {
            case .lineBreak(let br):
                while result.last == " " { result.removeLast() }
                result += br
            case .word(let w):
                if !result.isEmpty, result.last != "\n" { result += " " }
                result += w
            }
        }
        while result.last == " " || result.last == "\n" { result.removeLast() }
        return result
    }
}
```

- [ ] **Step 5: Run; all ten tests pass**

Run the Step 2 command. Expected: `** TEST SUCCEEDED **`. If a case differs by a space or a trailing punctuation mark, fix the processor, not the test — the tests encode the spec's examples. Note `scratch that` after "Buy eggs" deletes "Buy eggs" and keeps "Buy milk." because the break is the period; "Delete that. Buy bread" keeps the trailing "Buy bread".

- [ ] **Step 6: Commit**

```bash
git add app/justscribe/Models/DictationAction.swift app/justscribe/Services/Dictation app/justscribeTests/VoiceCommandProcessorTests.swift
git commit -m "Spoken commands while dictating: new line, new paragraph, scratch that, stop recording, send"
```

---

### Task 2: Vocabulary entries and the matcher

**Files:**
- Create: `app/justscribe/Models/VocabularyEntry.swift`, `app/justscribe/Services/Dictation/VocabularyMatcher.swift`
- Test: `app/justscribeTests/VocabularyMatcherTests.swift`

**Interfaces:**
- Produces: `VocabularyEntry { id, text, heardAs: [String], createdAt }`; `VocabularyMatcher.apply(words: [String], entries:, isDictionaryWord:) -> [String]` (same count; absorbed words become `""`), `VocabularyMatcher.apply(_ text: String, entries:, isDictionaryWord:) -> String`, `VocabularyMatcher.key(_:)`, `VocabularyMatcher.editDistance(_:_:)`, `VocabularyMatcher.phoneticKey(_:)`.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import justscribe

@Suite(.timeLimit(.minutes(1)))
struct VocabularyMatcherTests {

    private let dictionary: Set<String> = ["the", "a", "mark", "marc", "quantum", "swift", "ui", "send", "i", "met", "at", "noon", "and", "talked", "to", "yesterday", "hello", "world", "team", "open", "now", "file", "like", "by", "really", "lot"]
    private func isWord(_ w: String) -> Bool { dictionary.contains(w.lowercased()) }
    private func entry(_ text: String, _ heardAs: [String] = []) -> VocabularyEntry {
        VocabularyEntry(id: UUID(), text: text, heardAs: heardAs, createdAt: Date())
    }
    private func fix(_ text: String, _ entries: [VocabularyEntry]) -> String {
        VocabularyMatcher.apply(text, entries: entries, isDictionaryWord: isWord)
    }

    @Test func aHeardAsFormIsReplacedWhateverTheSpacingHyphensAndCase() {
        let e = [entry("SwiftUI", ["swift ui"])]
        #expect(fix("I like swift UI a lot", e) == "I like SwiftUI a lot")
        #expect(fix("I like Swift-ui, really", e) == "I like SwiftUI, really")
        #expect(fix("swift ui.", e) == "SwiftUI.")
    }

    @Test func aNonDictionaryWordThatSoundsLikeAnEntryIsReplaced() {
        let e = [entry("Quassum"), entry("Antoni")]
        #expect(fix("I met quasum at noon", e) == "I met Quassum at noon")
        #expect(fix("Antony and I talked", e) == "Antoni and I talked")
        #expect(fix("Hello, antoni!", e) == "Hello, Antoni!")
    }

    @Test func dictionaryWordsAreNeverReplacedBySound() {
        let e = [entry("Marc"), entry("Quassum")]
        #expect(fix("I met mark at noon", e) == "I met mark at noon")
        #expect(fix("quantum", e) == "quantum")
        // ...unless the user says so with a form.
        #expect(fix("I met mark at noon", [entry("Marc", ["mark"])]) == "I met Marc at noon")
    }

    @Test func distanceBoundsFollowTheKeyLength() {
        #expect(VocabularyMatcher.editDistance("antoni", "antony") == 1)
        #expect(VocabularyMatcher.editDistance("quasum", "quassum") == 1)
        #expect(VocabularyMatcher.editDistance("kitten", "sitting") == 3)
        #expect(fix("tteam", [entry("Team")]) == "Team")       // not a dictionary word; distance 1 is within the bound for a 4-letter key
        #expect(fix("teamed", [entry("Team")]) == "teamed")    // distance 2 is past the bound for a 4-letter key
    }

    @Test func phoneticKeysAgreeForKnownPairs() {
        #expect(VocabularyMatcher.phoneticKey("Antoni") == VocabularyMatcher.phoneticKey("Antony"))
        #expect(VocabularyMatcher.phoneticKey("Quassum") == VocabularyMatcher.phoneticKey("quasum"))
        #expect(VocabularyMatcher.phoneticKey("Smith") == VocabularyMatcher.phoneticKey("Smyth"))
        #expect(VocabularyMatcher.phoneticKey("John") == VocabularyMatcher.phoneticKey("Jon"))
        #expect(VocabularyMatcher.phoneticKey("Kristin") == VocabularyMatcher.phoneticKey("Christine"))
        #expect(VocabularyMatcher.phoneticKey("Antoni") != VocabularyMatcher.phoneticKey("Quassum"))
    }

    @Test func multiWordEntriesMatchRuns() {
        let e = [entry("Neural Sheet", ["neural sheets"])]
        #expect(fix("open neural sheets now", e) == "open Neural Sheet now")
        #expect(fix("the nural sheet file", e) == "the Neural Sheet file")
    }

    @Test func applyingTwiceChangesNothing() {
        let e = [entry("SwiftUI", ["swift ui"]), entry("Quassum"), entry("Antoni")]
        let once = fix("swift ui by quasum and antony", e)
        #expect(once == "SwiftUI by Quassum and Antoni")
        #expect(fix(once, e) == once)
    }

    @Test func theWordFormKeepsCountAndAffixes() {
        let words = [" I", " like", " swift", " UI,", " really"]
        let out = VocabularyMatcher.apply(words: words, entries: [entry("SwiftUI", ["swift ui"])], isDictionaryWord: isWord)
        #expect(out == [" I", " like", " SwiftUI,", "", " really"])
    }

    @Test func emptyInputsAreSafe() {
        #expect(fix("", [entry("X")]) == "")
        #expect(fix("hello world", []) == "hello world")
        #expect(VocabularyMatcher.apply(words: [], entries: [entry("X")], isDictionaryWord: isWord).isEmpty)
    }
}
```

- [ ] **Step 2: Run; it must fail to compile**

Run: `xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests/VocabularyMatcherTests 2>&1 | grep -E "error:|\*\* TEST" | head`
Expected: `error: cannot find 'VocabularyEntry' in scope`

- [ ] **Step 3: Write `VocabularyEntry.swift`**

```swift
import Foundation

/// A word or phrase the user wants spelled exactly so, with the ways the model tends to hear it.
nonisolated struct VocabularyEntry: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    /// Inserted exactly as written.
    var text: String
    /// Phrases that always become `text` (case-insensitive, spacing and hyphens ignored).
    var heardAs: [String]
    var createdAt: Date
}

/// The on-disk list. `version` lets a later format change migrate.
nonisolated struct VocabularyFile: Codable, Equatable, Sendable {
    static let currentVersion = 1
    var version: Int
    var entries: [VocabularyEntry]
    static let empty = VocabularyFile(version: currentVersion, entries: [])
}
```

- [ ] **Step 4: Write `VocabularyMatcher.swift`**

```swift
import Foundation

/// Puts the user's vocabulary into a transcript: explicit "heard as" forms first, then words the
/// model got wrong by sound or spelling. Pure; the dictionary check is injected.
nonisolated enum VocabularyMatcher {

    /// Letters and digits of a word, lower-cased, without diacritics, spaces or hyphens.
    static func key(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// Levenshtein distance.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    /// Metaphone-style phonetic key: words that sound alike share it.
    static func phoneticKey(_ word: String) -> String {
        var s = Array(key(word).filter { $0.isLetter })
        guard !s.isEmpty else { return "" }
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        // Silent initial pairs, and an initial "x" that sounds like "s".
        if s.count > 1 {
            let head = String(s[0...1])
            if ["kn", "gn", "pn", "ae", "wr"].contains(head) { s.removeFirst() }
            else if head == "wh" { s[1] = "w"; s.removeFirst() }
        }
        if s.first == "x" { s[0] = "s" }

        var out = ""
        func at(_ i: Int) -> Character? { i >= 0 && i < s.count ? s[i] : nil }
        func isVowel(_ c: Character?) -> Bool { c.map { vowels.contains($0) } ?? false }
        var i = 0
        while i < s.count {
            let c = s[i]
            defer { i += 1 }
            if c != "c", at(i - 1) == c { continue }           // doubled letters, except "cc"
            switch c {
            case "a", "e", "i", "o", "u", "y":
                if i == 0 { out += "a" }
            case "b":
                if !(i == s.count - 1 && at(i - 1) == "m") { out += "b" }
            case "c":
                if at(i + 1) == "i", at(i + 2) == "a" { out += "x" }
                else if at(i + 1) == "h" {
                    // "sch", "chr", "chl" sound like k (Christine); other "ch" like sh (Charles → x).
                    out += (at(i - 1) == "s" || ["r", "l"].contains(at(i + 2) ?? " ")) ? "k" : "x"; i += 1
                }
                else if ["i", "e", "y"].contains(at(i + 1) ?? " ") { out += "s" }
                else { out += "k" }
            case "d":
                if at(i + 1) == "g", ["e", "y", "i"].contains(at(i + 2) ?? " ") { out += "j"; i += 2 } else { out += "t" }
            case "g":
                if at(i + 1) == "h", !isVowel(at(i + 2)) { continue }
                if at(i + 1) == "n", i + 1 == s.count - 1 || (at(i + 2) == "e" && at(i + 3) == "d") { continue }
                if ["i", "e", "y"].contains(at(i + 1) ?? " ") { out += "j" } else { out += "k" }
            case "h":
                if isVowel(at(i - 1)), !isVowel(at(i + 1)) { continue }
                if ["c", "s", "p", "t", "g"].contains(at(i - 1) ?? " ") { continue }
                out += "h"
            case "k":
                if at(i - 1) != "c" { out += "k" }
            case "p":
                if at(i + 1) == "h" { out += "f"; i += 1 } else { out += "p" }
            case "q": out += "k"
            case "s":
                if at(i + 1) == "h" { out += "x"; i += 1 }
                else if at(i + 1) == "i", ["o", "a"].contains(at(i + 2) ?? " ") { out += "x" }
                else { out += "s" }
            case "t":
                if at(i + 1) == "i", ["o", "a"].contains(at(i + 2) ?? " ") { out += "x" }
                else if at(i + 1) == "h" { out += "0"; i += 1 }
                else if !(at(i + 1) == "c" && at(i + 2) == "h") { out += "t" }
            case "v": out += "f"
            case "w", "j":
                if c == "j" { out += "j" } else if isVowel(at(i + 1)) { out += "w" }
            case "x": out += "ks"
            case "z": out += "s"
            default: out += String(c)
            }
        }
        return out
    }

    // MARK: - Applying

    /// `words` as the model produced them (each may carry its own spaces and punctuation).
    /// Returns the same number of strings; a run that became one entry keeps its text in the
    /// first word and `""` in the rest, so callers can merge times.
    static func apply(words: [String], entries: [VocabularyEntry], isDictionaryWord: (String) -> Bool) -> [String] {
        guard !words.isEmpty, !entries.isEmpty else { return words }
        var tokens = words.map(Token.init)
        var locked = [Bool](repeating: false, count: tokens.count)
        let maxRun = 4

        // 1. Explicit forms, longest runs first so "swift ui" beats "ui".
        for run in stride(from: maxRun, through: 1, by: -1) {
            for entry in entries {
                let forms = entry.heardAs.map(key).filter { !$0.isEmpty }
                guard !forms.isEmpty else { continue }
                replaceRuns(of: run, in: &tokens, locked: &locked, with: entry.text) { runKey, _ in forms.contains(runKey) }
            }
        }
        // 2. Sound-alikes: runs of the entry's own word count, containing a non-dictionary word.
        for entry in entries {
            let entryWords = entry.text.split(whereSeparator: \.isWhitespace).map { key(String($0)) }.filter { !$0.isEmpty }
            guard !entryWords.isEmpty else { continue }
            let entryKey = entryWords.joined()
            let bound = entryKey.count <= 5 ? 1 : 2
            let entryPhonetic = phoneticKey(entryKey)
            replaceRuns(of: entryWords.count, in: &tokens, locked: &locked, with: entry.text) { runKey, runCores in
                guard runKey != entryKey else { return true }   // already right: keeps the pass idempotent
                guard runCores.contains(where: { !isDictionaryWord($0) }) else { return false }
                return editDistance(runKey, entryKey) <= bound || (!entryPhonetic.isEmpty && phoneticKey(runKey) == entryPhonetic)
            }
        }
        return tokens.map(\.text)
    }

    /// Free text: words keep their punctuation, and the whitespace between them (spaces, line
    /// breaks) is kept as it was; an absorbed word takes the whitespace before it with it.
    static func apply(_ text: String, entries: [VocabularyEntry], isDictionaryWord: (String) -> Bool) -> String {
        guard !text.isEmpty, !entries.isEmpty else { return text }
        var words: [String] = [], separators: [String] = []   // separators[i] precedes words[i]
        var word = "", gap = "", inWord = false
        for ch in text {
            if ch.isWhitespace {
                if inWord { words.append(word); word = ""; inWord = false }
                gap.append(ch)
            } else {
                if !inWord { separators.append(gap); gap = ""; inWord = true }
                word.append(ch)
            }
        }
        if inWord { words.append(word) }
        let fixed = apply(words: words, entries: entries, isDictionaryWord: isDictionaryWord)
        var result = ""
        for i in words.indices where !(fixed[i].isEmpty && !words[i].isEmpty) {
            result += separators[i] + fixed[i]
        }
        return result + gap
    }

    // MARK: - Private

    private struct Token {
        var leading: String
        var core: String
        var trailing: String
        init(_ s: String) {
            let coreStart = s.firstIndex(where: { $0.isLetter || $0.isNumber }) ?? s.endIndex
            let coreEnd = s.lastIndex(where: { $0.isLetter || $0.isNumber }).map { s.index(after: $0) } ?? coreStart
            leading = String(s[..<coreStart]); core = String(s[coreStart..<coreEnd]); trailing = String(s[coreEnd...])
        }
        var text: String { leading + core + trailing }
    }

    private static func replaceRuns(
        of length: Int, in tokens: inout [Token], locked: inout [Bool], with replacement: String,
        where matches: (_ runKey: String, _ runCores: [String]) -> Bool
    ) {
        guard length >= 1, tokens.count >= length else { return }
        var i = 0
        while i + length <= tokens.count {
            let range = i..<(i + length)
            let cores = range.map { tokens[$0].core }
            if !range.contains(where: { locked[$0] }), !cores.contains(where: \.isEmpty), matches(cores.map(key).joined(), cores) {
                var first = tokens[range.lowerBound]
                first.core = replacement
                first.trailing = tokens[range.upperBound - 1].trailing
                tokens[range.lowerBound] = first
                for j in range.dropFirst() { tokens[j] = Token(""); locked[j] = true }
                locked[range.lowerBound] = true
                i += length
            } else {
                i += 1
            }
        }
    }
}
```

- [ ] **Step 5: Run; all nine tests pass**

Run the Step 2 command. Expected: `** TEST SUCCEEDED **`. If a phonetic pair disagrees, print both keys in the failure and adjust the rule for that letter so both known pairs in the test agree; do not weaken the test to the implementation.

- [ ] **Step 6: Commit**

```bash
git add app/justscribe/Models/VocabularyEntry.swift app/justscribe/Services/Dictation/VocabularyMatcher.swift app/justscribeTests/VocabularyMatcherTests.swift
git commit -m "Vocabulary: spell the user's words right by their 'heard as' forms, spelling and sound"
```

---

### Task 3: Modes, the recording trigger, and the two stores

**Files:**
- Create: `app/justscribe/Models/DictationMode.swift`, `app/justscribe/Models/RecordingTrigger.swift`, `app/justscribe/Services/Dictation/JSONFile.swift`, `app/justscribe/Services/Dictation/VocabularyStore.swift`, `app/justscribe/Services/Dictation/ModeStore.swift`, `app/justscribe/Services/Dictation/VocabularyPrompt.swift`
- Test: `app/justscribeTests/DictationStoresTests.swift`

**Interfaces:**
- Produces: `DictationMode { id, name, instructions, cleanUp, appBundleIDs }` with `defaultID`, `defaultInstructions`, `makeDefault()`; `RecordingTrigger` (`hold`, `pressToToggle`; raw `hold`/`toggle`; `stored(_:)`, `title`, `detail`); `JSONFile.read/write/setAside`; `VocabularyStore` (`shared`, `init(fileURL:)`, `load()`, `entries`, `fileWasSetAside`, `add(text:heardAs:)`, `update(_:)`, `delete(_:)`, `importLines(_:) -> Int`); `ModeStore` (`shared`, `init(fileURL:)`, `load()`, `modes`, `fileWasSetAside`, `add(_:)`, `update(_:)`, `delete(_:)`, `mode(forApp:)`, `assign(app:to:)`); `VocabularyPrompt.text(_:)`.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import justscribe

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct DictationStoresTests {

    private func tempFile(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("justscribe-dictation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }
    private func cleanUp(_ url: URL) { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    // MARK: Vocabulary

    @Test func vocabularyRoundTripsAndKeepsNewestFirst() throws {
        let url = try tempFile("vocabulary.json"); defer { cleanUp(url) }
        let store = VocabularyStore(fileURL: url); store.load()
        #expect(store.entries.isEmpty)
        store.add(text: "Quassum", heardAs: [])
        store.add(text: "SwiftUI", heardAs: ["swift ui", " Swift-UI "])
        #expect(store.entries.map(\.text) == ["SwiftUI", "Quassum"])
        #expect(store.entries[0].heardAs == ["swift ui", "Swift-UI"])
        let again = VocabularyStore(fileURL: url); again.load()
        #expect(again.entries == store.entries)
    }

    @Test func vocabularyUpdateDeleteAndImport() throws {
        let url = try tempFile("vocabulary.json"); defer { cleanUp(url) }
        let store = VocabularyStore(fileURL: url); store.load()
        store.add(text: "Antoni", heardAs: [])
        var e = store.entries[0]; e.heardAs = ["antony"]; store.update(e)
        #expect(store.entries[0].heardAs == ["antony"])
        let added = store.importLines("""
            Quassum
            SwiftUI = swift ui, swift-ui

            Antoni
            """)
        #expect(added == 2)   // Antoni already exists
        #expect(store.entries.map(\.text) == ["SwiftUI", "Quassum", "Antoni"])
        #expect(store.entries[0].heardAs == ["swift ui", "swift-ui"])
        store.delete(store.entries[0].id)
        #expect(store.entries.map(\.text) == ["Quassum", "Antoni"])
    }

    @Test func aDamagedVocabularyFileIsSetAside() throws {
        let url = try tempFile("vocabulary.json"); defer { cleanUp(url) }
        try "nope".write(to: url, atomically: true, encoding: .utf8)
        let store = VocabularyStore(fileURL: url); store.load()
        #expect(store.entries.isEmpty)
        #expect(store.fileWasSetAside)
        #expect(FileManager.default.fileExists(atPath: url.path + ".broken"))
    }

    // MARK: Modes

    @Test func modesStartWithDefaultAndKeepItFirst() throws {
        let url = try tempFile("modes.json"); defer { cleanUp(url) }
        let store = ModeStore(fileURL: url); store.load()
        #expect(store.modes.map(\.name) == ["Default"])
        #expect(store.modes[0].id == DictationMode.defaultID)
        #expect(store.modes[0].instructions == DictationMode.defaultInstructions)
        store.add(DictationMode(id: UUID(), name: "Email", instructions: "Formal.", cleanUp: true, appBundleIDs: ["com.apple.mail"]))
        let again = ModeStore(fileURL: url); again.load()
        #expect(again.modes.map(\.name) == ["Default", "Email"])
    }

    @Test func anAppBelongsToOneModeAndSelectionFallsBackToDefault() throws {
        let url = try tempFile("modes.json"); defer { cleanUp(url) }
        let store = ModeStore(fileURL: url); store.load()
        let email = DictationMode(id: UUID(), name: "Email", instructions: "Formal.", cleanUp: true, appBundleIDs: ["com.apple.mail"])
        let code = DictationMode(id: UUID(), name: "Code", instructions: "", cleanUp: false, appBundleIDs: [])
        store.add(email); store.add(code)
        #expect(store.mode(forApp: "com.apple.mail").name == "Email")
        #expect(store.mode(forApp: "com.apple.Notes").name == "Default")
        #expect(store.mode(forApp: nil).name == "Default")
        store.assign(app: "com.apple.mail", to: code.id)
        #expect(store.mode(forApp: "com.apple.mail").name == "Code")
        #expect(store.modes.first { $0.id == email.id }?.appBundleIDs.isEmpty == true)
    }

    @Test func defaultCannotBeDeletedAndBlankInstructionsFallBack() throws {
        let url = try tempFile("modes.json"); defer { cleanUp(url) }
        let store = ModeStore(fileURL: url); store.load()
        store.delete(DictationMode.defaultID)
        #expect(store.modes.count == 1)
        var d = store.modes[0]; d.instructions = "   "; store.update(d)
        #expect(store.modes[0].effectiveInstructions == DictationMode.defaultInstructions)
    }

    @Test func aDamagedModesFileIsSetAsideAndDefaultRecreated() throws {
        let url = try tempFile("modes.json"); defer { cleanUp(url) }
        try "nope".write(to: url, atomically: true, encoding: .utf8)
        let store = ModeStore(fileURL: url); store.load()
        #expect(store.fileWasSetAside)
        #expect(store.modes.map(\.name) == ["Default"])
    }

    // MARK: Trigger and prompt

    @Test func recordingTriggerStoresAndDefaults() {
        #expect(RecordingTrigger.stored(nil) == .hold)
        #expect(RecordingTrigger.stored("toggle") == .pressToToggle)
        #expect(RecordingTrigger.stored("garbage") == .hold)
        #expect(RecordingTrigger.pressToToggle.rawValue == "toggle")
    }

    @Test func vocabularyPromptListsNewestFirst() {
        let old = VocabularyEntry(id: UUID(), text: "Quassum", heardAs: [], createdAt: Date(timeIntervalSince1970: 1))
        let new = VocabularyEntry(id: UUID(), text: "SwiftUI", heardAs: ["swift ui"], createdAt: Date(timeIntervalSince1970: 2))
        #expect(VocabularyPrompt.text([old, new]) == "SwiftUI Quassum")
        #expect(VocabularyPrompt.text([]) == "")
    }
}
```

- [ ] **Step 2: Run; it must fail to compile**

Run: `xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests/DictationStoresTests 2>&1 | grep -E "error:|\*\* TEST" | head`
Expected: `error: cannot find 'VocabularyStore' in scope`

- [ ] **Step 3: Write `DictationMode.swift` and `RecordingTrigger.swift`**

```swift
import Foundation

/// How dictated text is cleaned up for a set of apps.
nonisolated struct DictationMode: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    /// What the clean-up model is told to do; blank falls back to Default's.
    var instructions: String
    /// Off: the raw transcript (after commands and vocabulary) goes to these apps.
    var cleanUp: Bool
    var appBundleIDs: [String]

    static let defaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let defaultInstructions = "Fix grammar, spelling and punctuation. Preserve the meaning and tone."

    static func makeDefault() -> DictationMode {
        DictationMode(id: defaultID, name: "Default", instructions: defaultInstructions, cleanUp: true, appBundleIDs: [])
    }

    var isDefault: Bool { id == Self.defaultID }

    var effectiveInstructions: String {
        let trimmed = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultInstructions : trimmed
    }
}

nonisolated struct ModesFile: Codable, Equatable, Sendable {
    static let currentVersion = 1
    var version: Int
    var modes: [DictationMode]
}
```

```swift
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
        case .pressToToggle: "Say \"stop recording\" or press the shortcut again to finish. A recording stops by itself after 10 minutes."
        }
    }
}
```

- [ ] **Step 4: Write `JSONFile.swift`**

```swift
import Foundation

/// One JSON document in the container: atomic writes, ISO 8601 dates, and a damaged file set
/// aside as `<name>.broken` rather than overwritten.
nonisolated enum JSONFile {
    enum ReadResult<T> { case missing, loaded(T), damaged }

    static func read<T: Decodable>(_ type: T.Type, from url: URL) -> ReadResult<T> {
        guard let data = try? Data(contentsOf: url) else { return .missing }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let value = try? decoder.decode(T.self, from: data) { return .loaded(value) }
        return .damaged
    }

    /// Moves a damaged file out of the way; a previous `.broken` is replaced.
    static func setAside(_ url: URL) {
        let broken = url.appendingPathExtension("broken")
        try? FileManager.default.removeItem(at: broken)
        try? FileManager.default.moveItem(at: url, to: broken)
    }

    @discardableResult
    static func write<T: Encodable>(_ value: T, to url: URL) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(value).write(to: url, options: .atomic)
            return true
        } catch {
            print("JSONFile: \(url.lastPathComponent) not saved: \(error)")
            return false
        }
    }

    /// `Application Support/<bundle id>/<name>` inside the container.
    static func containerURL(_ name: String) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "com.quassum.justscribe"
        return support.appendingPathComponent(bundleID).appendingPathComponent(name)
    }
}
```

- [ ] **Step 5: Write `VocabularyStore.swift`**

```swift
import Foundation
import Observation

/// The user's vocabulary, newest first, in `vocabulary.json`.
@Observable
final class VocabularyStore {
    static let shared = VocabularyStore(fileURL: JSONFile.containerURL("vocabulary.json"))

    private(set) var entries: [VocabularyEntry] = []
    private(set) var fileWasSetAside = false
    private let fileURL: URL

    init(fileURL: URL) { self.fileURL = fileURL }

    func load() {
        switch JSONFile.read(VocabularyFile.self, from: fileURL) {
        case .missing: entries = []
        case .loaded(let file): entries = file.entries.sorted { $0.createdAt > $1.createdAt }
        case .damaged: JSONFile.setAside(fileURL); fileWasSetAside = true; entries = []
        }
    }

    func add(text: String, heardAs: [String]) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }
        let forms = Self.cleanForms(heardAs)
        entries.insert(VocabularyEntry(id: UUID(), text: cleanText, heardAs: forms, createdAt: Date()), at: 0)
        save()
    }

    func update(_ entry: VocabularyEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var entry = entry
        entry.text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.heardAs = Self.cleanForms(entry.heardAs)
        entries[index] = entry
        save()
    }

    func delete(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    /// One entry per non-empty line: `text` or `text = form, form`. Skips texts already present.
    /// Returns how many were added.
    @discardableResult
    func importLines(_ lines: String) -> Int {
        var added = 0
        let existing = Set(entries.map { $0.text.lowercased() })
        var seen = existing
        for line in lines.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let text = parts.first, !text.isEmpty, !seen.contains(text.lowercased()) else { continue }
            let forms = parts.count > 1 ? Self.cleanForms(parts[1].split(separator: ",").map(String.init)) : []
            entries.insert(VocabularyEntry(id: UUID(), text: text, heardAs: forms, createdAt: Date()), at: 0)
            seen.insert(text.lowercased())
            added += 1
        }
        if added > 0 { save() }
        return added
    }

    private static func cleanForms(_ forms: [String]) -> [String] {
        forms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func save() {
        JSONFile.write(VocabularyFile(version: VocabularyFile.currentVersion, entries: entries), to: fileURL)
    }
}
```

- [ ] **Step 6: Write `ModeStore.swift`**

```swift
import Foundation
import Observation

/// The dictation modes, Default first, in `modes.json`.
@Observable
final class ModeStore {
    static let shared = ModeStore(fileURL: JSONFile.containerURL("modes.json"))

    private(set) var modes: [DictationMode] = []
    private(set) var fileWasSetAside = false
    private let fileURL: URL

    init(fileURL: URL) { self.fileURL = fileURL }

    func load() {
        switch JSONFile.read(ModesFile.self, from: fileURL) {
        case .missing: modes = []
        case .loaded(let file): modes = file.modes
        case .damaged: JSONFile.setAside(fileURL); fileWasSetAside = true; modes = []
        }
        ensureDefault()
    }

    func add(_ mode: DictationMode) {
        var mode = mode
        mode.appBundleIDs = Array(Set(mode.appBundleIDs)).sorted()
        releaseApps(mode.appBundleIDs, except: mode.id)
        modes.append(mode)
        ensureDefault()
        save()
    }

    func update(_ mode: DictationMode) {
        guard let index = modes.firstIndex(where: { $0.id == mode.id }) else { return }
        var mode = mode
        if mode.isDefault { mode.appBundleIDs = []; mode.name = "Default" }
        releaseApps(mode.appBundleIDs, except: mode.id)
        modes[index] = mode
        save()
    }

    func delete(_ id: UUID) {
        guard id != DictationMode.defaultID else { return }
        modes.removeAll { $0.id == id }
        save()
    }

    /// The mode listing the app, else Default.
    func mode(forApp bundleID: String?) -> DictationMode {
        if let bundleID, let mode = modes.first(where: { $0.appBundleIDs.contains(bundleID) }) { return mode }
        return modes.first { $0.isDefault } ?? DictationMode.makeDefault()
    }

    /// Moves an app to one mode; it leaves whichever mode listed it before.
    func assign(app bundleID: String, to modeID: UUID) {
        guard let index = modes.firstIndex(where: { $0.id == modeID }), modeID != DictationMode.defaultID else { return }
        releaseApps([bundleID], except: modeID)
        if !modes[index].appBundleIDs.contains(bundleID) { modes[index].appBundleIDs.append(bundleID) }
        save()
    }

    private func releaseApps(_ apps: [String], except modeID: UUID) {
        for i in modes.indices where modes[i].id != modeID {
            modes[i].appBundleIDs.removeAll { apps.contains($0) }
        }
    }

    private func ensureDefault() {
        if let index = modes.firstIndex(where: { $0.isDefault }) {
            if index != 0 { modes.insert(modes.remove(at: index), at: 0) }
        } else {
            modes.insert(DictationMode.makeDefault(), at: 0)
            save()
        }
    }

    private func save() {
        JSONFile.write(ModesFile(version: ModesFile.currentVersion, modes: modes), to: fileURL)
    }
}
```

- [ ] **Step 7: Write `VocabularyPrompt.swift`**

```swift
import Foundation

/// The vocabulary as Whisper's initial prompt: the words the user wants, newest first.
nonisolated enum VocabularyPrompt {
    static func text(_ entries: [VocabularyEntry]) -> String {
        entries.sorted { $0.createdAt > $1.createdAt }.map(\.text).joined(separator: " ")
    }
}
```

- [ ] **Step 8: Run; all nine tests pass**

Run the Step 2 command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 9: Commit**

```bash
git add app/justscribe/Models/DictationMode.swift app/justscribe/Models/RecordingTrigger.swift app/justscribe/Services/Dictation app/justscribeTests/DictationStoresTests.swift
git commit -m "Keep the vocabulary and the dictation modes in the app's container"
```

---

### Task 4: The dictation pipeline

**Files:**
- Create: `app/justscribe/Services/Dictation/DictationPipeline.swift`, `app/justscribe/Services/Dictation/DictionaryWords.swift`
- Test: `app/justscribeTests/DictationPipelineTests.swift`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: `DictationContext`, `DictationResult`, `DictationPipeline(cleanUp:isDictionaryWord:)`, `func process(_ raw: String, context: DictationContext) async -> DictationResult`; `DictionaryWords.isWord(_:language:)`.

- [ ] **Step 1: Write the failing tests**

```swift
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
}
```

- [ ] **Step 2: Run; it must fail to compile**

Run: `xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests/DictationPipelineTests 2>&1 | grep -E "error:|\*\* TEST" | head`
Expected: `error: cannot find 'DictationPipeline' in scope`

- [ ] **Step 3: Write `DictionaryWords.swift`**

```swift
import AppKit

/// Whether a word is in the system dictionary for a language — the guard that keeps vocabulary
/// sound-alike matching away from ordinary words. Main actor: `NSSpellChecker` is AppKit.
enum DictionaryWords {
    private static var cache: [String: Bool] = [:]

    static func isWord(_ word: String, language: String?) -> Bool {
        let key = (language ?? "") + "|" + word.lowercased()
        if let cached = cache[key] { return cached }
        let checker = NSSpellChecker.shared
        let range = checker.checkSpelling(of: word, startingAt: 0, language: language, wrap: false,
                                          inSpellDocumentWithTag: 0, wordCount: nil)
        let result = range.location == NSNotFound
        if cache.count > 20_000 { cache.removeAll() }
        cache[key] = result
        return result
    }
}
```

- [ ] **Step 4: Write `DictationPipeline.swift`**

```swift
import Foundation

/// Everything a dictation needs to be turned into the text that is inserted.
nonisolated struct DictationContext: Sendable {
    var voiceCommands: Bool
    var spokenPunctuation: Bool
    /// Session commands ("stop recording", "send") act only in press-to-toggle mode.
    var pressToToggle: Bool
    var vocabulary: [VocabularyEntry]
    var mode: DictationMode
    /// The global Clean-up switch.
    var cleanUpEnabled: Bool
    var language: String?
}

nonisolated struct DictationResult: Equatable, Sendable {
    var text: String
    var actions: [DictationAction]
}

/// Raw transcript → voice commands → vocabulary → clean-up with the mode's instructions.
/// Pure except for clean-up and the dictionary check, which are injected.
final class DictationPipeline {
    typealias CleanUp = (_ text: String, _ instructions: String, _ language: String?) async throws -> String

    private let cleanUp: CleanUp
    private let isDictionaryWord: (String) -> Bool

    init(cleanUp: @escaping CleanUp, isDictionaryWord: @escaping (String) -> Bool) {
        self.cleanUp = cleanUp
        self.isDictionaryWord = isDictionaryWord
    }

    func process(_ raw: String, context: DictationContext) async -> DictationResult {
        let commanded = VoiceCommandProcessor.apply(
            raw, commandsOn: context.voiceCommands, punctuationOn: context.spokenPunctuation,
            sessionCommandsOn: context.pressToToggle)
        var text = VocabularyMatcher.apply(commanded.text, entries: context.vocabulary, isDictionaryWord: isDictionaryWord)

        if context.cleanUpEnabled, context.mode.cleanUp, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                let cleaned = try await cleanUp(text, context.mode.effectiveInstructions, context.language)
                if !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { text = cleaned }
            } catch {
                print("Clean-up failed, keeping the text as dictated: \(error)")
            }
        }
        return DictationResult(text: text, actions: commanded.actions)
    }

    /// The session command the streamed text ends with — checked live while recording.
    nonisolated static func terminatingCommand(in streamed: String, context: DictationContext) -> DictationAction? {
        guard context.voiceCommands else { return nil }
        return VoiceCommandProcessor.terminatingCommand(in: streamed, sessionCommandsOn: context.pressToToggle)
    }
}
```

- [ ] **Step 5: Run; all six tests pass**

Run the Step 2 command. Expected: `** TEST SUCCEEDED **`. (`DictationPipeline` is main-actor by the target default, which the `@MainActor` test suite satisfies; `FakeCleanUp.run` is passed as the closure.)

- [ ] **Step 6: Commit**

```bash
git add app/justscribe/Services/Dictation/DictationPipeline.swift app/justscribe/Services/Dictation/DictionaryWords.swift app/justscribeTests/DictationPipelineTests.swift
git commit -m "One pipeline turns a transcript into the text that is inserted: commands, vocabulary, clean-up"
```

---

### Task 5: Clean-up instructions through the grammar backends

**Files:**
- Create: `app/justscribe/Services/Grammar/GrammarPrompt.swift`
- Modify: `app/justscribe/Services/Grammar/GrammarBackend.swift`, `AppleFoundationGrammarBackend.swift`, `MLXGrammarBackend.swift`, `app/justscribe/Services/GrammarCorrectionService.swift`, `app/justscribe/AppDelegate.swift` (one call site)
- Test: `app/justscribeTests/GrammarPromptTests.swift`

**Interfaces:**
- Produces: `GrammarPrompt.frame(_ instructions: String) -> String`; `GrammarBackend.correct(_ text: String, instructions: String, language: String?)`; `GrammarCorrectionService.correctGrammar(_ text: String, instructions: String, language: String?)`.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import justscribe

@Suite(.timeLimit(.minutes(1)))
struct GrammarPromptTests {
    @Test func theFrameWrapsTheInstructionsAndKeepsTheOutputContract() {
        let framed = GrammarPrompt.frame("Formal, British spelling.")
        #expect(framed.hasPrefix("Formal, British spelling.\n\n"))
        #expect(framed.hasSuffix("Apply this to the text that follows. Output only the resulting text: no explanations, no quotes, no preamble."))
    }

    @Test func blankInstructionsFallBackToDefault() {
        #expect(GrammarPrompt.frame("  \n") == GrammarPrompt.frame(DictationMode.defaultInstructions))
    }
}
```

- [ ] **Step 2: Run; it must fail to compile**

Run: `xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests/GrammarPromptTests 2>&1 | grep -E "error:|\*\* TEST" | head`
Expected: `error: cannot find 'GrammarPrompt' in scope`

- [ ] **Step 3: Write `GrammarPrompt.swift`**

```swift
import Foundation

/// The system prompt both clean-up backends use: the mode's instructions inside a fixed frame
/// that keeps the model answering with text only.
nonisolated enum GrammarPrompt {
    static let contract = "Apply this to the text that follows. Output only the resulting text: no explanations, no quotes, no preamble."

    static func frame(_ instructions: String) -> String {
        let trimmed = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmed.isEmpty ? DictationMode.defaultInstructions : trimmed
        return body + "\n\n" + contract
    }
}
```

- [ ] **Step 4: Thread `instructions` through the protocol and backends**

In `GrammarBackend.swift`, change the protocol requirement to:

```swift
    func correct(_ text: String, instructions: String, language: String?) async throws -> String
```

In `AppleFoundationGrammarBackend.swift`:
- Delete the `private static let instructions = """…"""` constant.
- `prepare`: `let session = makeSession(instructions: GrammarPrompt.frame(DictationMode.defaultInstructions))`.
- `makeSession` becomes `private func makeSession(instructions: String) -> LanguageModelSession { LanguageModelSession(instructions: instructions) }`.
- `correct(_ text: String, instructions: String, language: String?)`: compute `let framed = GrammarPrompt.frame(instructions)` once and pass it to every `correctOne(…, instructions: framed, language:)` call (both the single-shot and the chunk loop).
- `correctOne(_ text: String, instructions: String, language: String?)`: the prewarmed session is used only for Default's instructions:

```swift
        let session: LanguageModelSession
        if let warm = warmSession, instructions == GrammarPrompt.frame(DictationMode.defaultInstructions) {
            session = warm
        } else {
            session = makeSession(instructions: instructions)
        }
        warmSession = nil
```

In `MLXGrammarBackend.swift`:
- Delete `systemPrompt`; in `prepare`, create the `ChatSession` with `GrammarPrompt.frame(DictationMode.defaultInstructions)` (it is only a warm placeholder).
- `correct(_ text: String, instructions: String, language: String?)`: keep the `chatSession == nil → notReady` guard for readiness, then build a fresh session per request over the loaded container:

```swift
        guard chatSession != nil, let container = modelContainer else { throw GrammarBackendError.notReady }
        let session = ChatSession(
            container,
            instructions: GrammarPrompt.frame(instructions),
            generateParameters: GenerateParameters(maxTokens: 2048, temperature: 0.1)
        )
```

and use `session.respond(to: prompt)` as before (no `clear()` needed on a fresh session).

In `GrammarCorrectionService.swift`:

```swift
    func correctGrammar(_ text: String, instructions: String, language: String? = nil) async throws -> String {
        guard let backend = activeBackend else { throw GrammarBackendError.notReady }
        isProcessing = true
        defer { isProcessing = false }
        let corrected = try await backend.correct(text, instructions: instructions, language: language)
        print("Clean-up: '\(text)' -> '\(corrected)'")
        return corrected
    }
```

In `AppDelegate.swift`, the existing call becomes `GrammarCorrectionService.shared.correctGrammar(finalTranscription, instructions: DictationMode.defaultInstructions, language: language)` — a placeholder so the app builds; Task 7 replaces this whole block with the pipeline.

- [ ] **Step 5: Build, run the suite, commit**

```bash
xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests 2>&1 | grep -E "error:|\*\* TEST" | tail -3
git add app/justscribe/Services/Grammar app/justscribe/Services/GrammarCorrectionService.swift app/justscribe/AppDelegate.swift app/justscribeTests/GrammarPromptTests.swift
git commit -m "Clean-up takes its instructions per dictation instead of one fixed prompt"
```

Expected: `** TEST SUCCEEDED **`.

---

### Task 6: Settings keys, the Recording picker and the Behavior switches

**Files:**
- Modify: `app/justscribe/Models/AppSettings.swift`, `app/justscribe/Views/Settings/Sections/ShortcutSettingsSection.swift`, `app/justscribe/Views/Settings/Sections/BehaviorSettingsSection.swift`

**Interfaces:**
- Produces: `AppSettings.recordingTriggerKey`, `voiceCommandsEnabledKey`, `spokenPunctuationEnabledKey`; fields `recordingTrigger: RecordingTrigger` (via `recordingTriggerRaw`), `voiceCommandsEnabled: Bool = true`, `spokenPunctuationEnabled: Bool = false`.

- [ ] **Step 1: `AppSettings.swift`** — after `historyKeepsAudioKey`:

```swift
    static let recordingTriggerKey = "recordingTrigger"
    static let voiceCommandsEnabledKey = "voiceCommandsEnabled"
    static let spokenPunctuationEnabledKey = "spokenPunctuationEnabled"
```

After the `textInsertionMode` property (same `…Raw` + computed pattern):

```swift
    // How the shortcut drives a recording
    @Attribute var recordingTriggerRaw: String = RecordingTrigger.defaultTrigger.rawValue
    var recordingTrigger: RecordingTrigger {
        get { RecordingTrigger.stored(recordingTriggerRaw) }
        set {
            recordingTriggerRaw = newValue.rawValue
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.recordingTriggerKey)
        }
    }

    // Voice commands
    var voiceCommandsEnabled: Bool = true {
        didSet { UserDefaults.standard.set(voiceCommandsEnabled, forKey: Self.voiceCommandsEnabledKey) }
    }
    var spokenPunctuationEnabled: Bool = false {
        didSet { UserDefaults.standard.set(spokenPunctuationEnabled, forKey: Self.spokenPunctuationEnabledKey) }
    }
```

In `syncToUserDefaults()`:

```swift
        UserDefaults.standard.set(recordingTriggerRaw, forKey: Self.recordingTriggerKey)
        UserDefaults.standard.set(voiceCommandsEnabled, forKey: Self.voiceCommandsEnabledKey)
        UserDefaults.standard.set(spokenPunctuationEnabled, forKey: Self.spokenPunctuationEnabledKey)
```

Because `voiceCommandsEnabled` defaults to `true` but UserDefaults' `bool(forKey:)` defaults to `false` before the first sync, every runtime read uses the helper added in Task 7 (`UserDefaults.standard.object(forKey:) == nil ? true : bool(forKey:)`), the same way `copyToClipboard` is read.

- [ ] **Step 2: `ShortcutSettingsSection.swift`** — it takes no settings today; give it `@Bindable var settings: AppSettings` (and update the call in `SettingsView.swift` to `ShortcutSettingsSection(settings: settings)`). After the `HStack` holding the recorder and before the "Default:" text, add:

```swift
                Divider()

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "record.circle")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recording")
                            .font(.body)
                        Picker("", selection: Binding(
                            get: { settings.recordingTrigger },
                            set: { settings.recordingTrigger = $0 }
                        )) {
                            ForEach(RecordingTrigger.allCases, id: \.self) { trigger in
                                Text(trigger.title).tag(trigger)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.radioGroup)
                        Text(settings.recordingTrigger.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
```

Change the tip at the bottom to: `"Tip: Modifier-only shortcuts like Control + Shift work too."`

- [ ] **Step 3: `BehaviorSettingsSection.swift`** — after the "Copy to Clipboard" row:

```swift
                Divider()

                ToggleSettingsRow(
                    title: "Voice Commands",
                    subtitle: "Say \"new line\", \"new paragraph\", \"scratch that\", \"stop recording\" or \"send\" while dictating",
                    systemImage: "waveform.and.mic",
                    isOn: Binding(
                        get: { settings.voiceCommandsEnabled },
                        set: { settings.voiceCommandsEnabled = $0 }
                    )
                )

                ToggleSettingsRow(
                    title: "Spoken Punctuation",
                    subtitle: "Say \"period\", \"comma\", \"question mark\", \"open quote\"… to punctuate",
                    systemImage: "textformat.abc.dottedunderline",
                    isOn: Binding(
                        get: { settings.spokenPunctuationEnabled },
                        set: { settings.spokenPunctuationEnabled = $0 }
                    )
                )
                .disabled(!settings.voiceCommandsEnabled)
                .opacity(settings.voiceCommandsEnabled ? 1 : 0.5)
```

- [ ] **Step 4: Build, run the suite, commit**

```bash
xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests 2>&1 | grep -E "error:|\*\* TEST" | tail -3
git add app/justscribe/Models/AppSettings.swift app/justscribe/Views/Settings
git commit -m "Settings: choose hold or press-to-toggle recording, and turn voice commands and spoken punctuation on or off"
```

---

### Task 7: Press-to-toggle, the pipeline, actions and the Whisper prompt in the app

**Files:**
- Modify: `app/justscribe/AppDelegate.swift`, `app/justscribe/Services/ClipboardService.swift`, `app/justscribe/Managers/OverlayManager.swift`, `app/justscribe/Services/TranscriptionService.swift`

**Interfaces:**
- Consumes: Tasks 1–6.
- Produces: `ClipboardService.pressReturn()`; `OverlayManager.listeningHint: String?`, `OverlayManager.onTap: (() -> Void)?`; `TranscriptionService.vocabularyPromptText: String?`.

- [ ] **Step 1: `ClipboardService.swift`** — after `paste(...)`:

```swift
    /// One Return keystroke, after a paste that ended with "send".
    func pressReturn() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Return), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Return), keyDown: false)
        keyDown?.flags = []
        keyUp?.flags = []
        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)
    }
```

- [ ] **Step 2: `OverlayManager.swift`**

Add two properties next to `state`:

```swift
    /// Shown under "Listening..." instead of "Speak now" (press mode, the mode's name).
    var listeningHint: String?
    /// Set while a press-to-toggle recording runs: a click on the overlay stops it.
    var onTap: (() -> Void)?
```

`descriptionText` for `.listening` returns `listeningHint ?? "Speak now"`. In `hide()`, also set `listeningHint = nil` and `onTap = nil`. In `OverlayExpandedView` (same file), add to the outer `HStack` (the one holding `iconView`, the texts and the close button): `.contentShape(Rectangle()).onTapGesture { manager.onTap?() }`.

- [ ] **Step 3: `TranscriptionService.swift`** — a stored property near `whisperKit`:

```swift
    /// The user's vocabulary as Whisper's initial prompt; nil or empty means none. Parakeet ignores it.
    var vocabularyPromptText: String?
```

In `transcribeWithWhisperKit`, after `options.language` is set:

```swift
            if let promptText = vocabularyPromptText, !promptText.isEmpty, let tokenizer = whisperKit.tokenizer {
                let begin = tokenizer.specialTokens.specialTokenBegin
                let tokens = tokenizer.encode(text: " " + promptText).filter { $0 < begin }
                if !tokens.isEmpty { options.promptTokens = Array(tokens.prefix(200)) }
            }
```

(`specialTokens.specialTokenBegin` exists on `WhisperTokenizer`; if the build says otherwise, filter with `$0 < 50257` and leave a comment naming the Whisper vocabulary size.)

- [ ] **Step 4: `AppDelegate.swift`**

Add stored state next to `insertionMode`:

```swift
    /// Read at key down and kept for the session, so a change in Settings mid-dictation cannot
    /// orphan a press-mode recording or switch the mode under it.
    private var sessionTrigger = RecordingTrigger.defaultTrigger
    private var sessionContext: DictationContext?
    private var safetyStopTask: Task<Void, Never>?
    private static let safetyStop: Duration = .seconds(600)

    private lazy var pipeline = DictationPipeline(
        cleanUp: { text, instructions, language in
            try await GrammarCorrectionService.shared.correctGrammar(text, instructions: instructions, language: language)
        },
        isDictionaryWord: { [weak self] word in
            DictionaryWords.isWord(word, language: self?.sessionContext?.language)
        }
    )

    private static func boolDefault(_ key: String, _ fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil ? fallback : UserDefaults.standard.bool(forKey: key)
    }
```

Replace `handleHotkeyDown` and `handleHotkeyUp`:

```swift
    @MainActor
    private func handleHotkeyDown() {
        switch sessionState {
        case .idle:
            sessionTrigger = RecordingTrigger.stored(UserDefaults.standard.string(forKey: AppSettings.recordingTriggerKey))
            startRecording()
        case .recording where sessionTrigger == .pressToToggle:
            print("Press-to-toggle: stopping")
            Task { await stopRecordingAndFinalize() }
        default:
            print("Not idle (state: \(sessionState)), ignoring key down")
        }
    }

    @MainActor
    private func handleHotkeyUp() {
        guard sessionState == .recording, sessionTrigger == .hold else {
            print("Key up ignored (state: \(sessionState), trigger: \(sessionTrigger))")
            return
        }
        Task { await stopRecordingAndFinalize() }
    }
```

In `beginRecording()`, after `insertionMode = …`, build the session context and the overlay hint, and arm the safety stop (the overlay call `OverlayManager.shared.showListening()` stays where it is, but set the hint *before* it):

```swift
        // The app in front decides the mode; everything is read now and kept for the session.
        let frontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let mode = ModeStore.shared.mode(forApp: frontApp)
        sessionContext = DictationContext(
            voiceCommands: Self.boolDefault(AppSettings.voiceCommandsEnabledKey, true),
            spokenPunctuation: UserDefaults.standard.bool(forKey: AppSettings.spokenPunctuationEnabledKey),
            pressToToggle: sessionTrigger == .pressToToggle,
            vocabulary: VocabularyStore.shared.entries,
            mode: mode,
            cleanUpEnabled: UserDefaults.standard.bool(forKey: AppSettings.grammarCorrectionEnabledKey),
            language: UserDefaults.standard.string(forKey: AppSettings.selectedLanguageKey))
        TranscriptionService.shared.vocabularyPromptText = VocabularyPrompt.text(VocabularyStore.shared.entries)

        var hint: [String] = []
        if sessionTrigger == .pressToToggle { hint.append("Press the shortcut to stop") }
        if !mode.isDefault { hint.append(mode.name) }
        OverlayManager.shared.listeningHint = hint.isEmpty ? nil : hint.joined(separator: " · ")
        OverlayManager.shared.onTap = sessionTrigger == .pressToToggle ? { [weak self] in self?.handleHotkeyDown() } : nil

        safetyStopTask?.cancel()
        if sessionTrigger == .pressToToggle {
            safetyStopTask = Task { [weak self] in
                try? await Task.sleep(for: Self.safetyStop)
                guard !Task.isCancelled, let self, self.sessionState == .recording else { return }
                print("Safety stop after 10 minutes")
                self.stoppedBySafety = true
                await self.stopRecordingAndFinalize()
            }
        }
```

Add `private var stoppedBySafety = false` next to the other session fields. Move the existing `let language = …` line in `beginRecording` to use `sessionContext?.language` or leave it; both read the same key.

In the streaming callback inside `beginRecording`, make the callback run for both insertion modes and add live detection **before** the `insertsWhileSpeaking` guard:

```swift
        TranscriptionService.shared.onTranscriptionUpdate = { [weak self] text in
            guard let self else { return }
            if let context = self.sessionContext, self.sessionState == .recording,
               DictationPipeline.terminatingCommand(in: text, context: context) != nil {
                print("Spoken session command heard; stopping")
                Task { await self.stopRecordingAndFinalize() }
                return
            }
            guard self.insertionMode.insertsWhileSpeaking else { return }
            // (existing delta-typing body unchanged)
```

In `stopRecordingAndFinalize()`: at the top, after `sessionState = .finalizing`, add `safetyStopTask?.cancel(); safetyStopTask = nil; OverlayManager.shared.onTap = nil`. Replace the whole grammar-correction block (from `// Grammar correction (if enabled and model is loaded)` through its closing brace) with:

```swift
        // Commands, vocabulary and clean-up, with the mode the app in front chose at key down.
        var actions: [DictationAction] = []
        if let context = sessionContext, !finalTranscription.isEmpty {
            let needsModel = context.cleanUpEnabled && context.mode.cleanUp && GrammarCorrectionService.shared.isModelLoaded
            if needsModel { OverlayManager.shared.showProcessing() }
            var effective = context
            effective.cleanUpEnabled = needsModel
            let result = await pipeline.process(finalTranscription, context: effective)
            actions = result.actions
            if result.text != finalTranscription {
                if insertionMode.insertsWhileSpeaking {
                    ClipboardService.shared.replaceTypedText(characterCount: finalTranscription.count, withText: result.text)
                }
                finalTranscription = result.text
            }
        }
```

After the paste `switch` (the `case .paste … case .nothing` block) add:

```swift
        if actions.contains(.pressReturn), !finalTranscription.isEmpty {
            // The pasted text must land before Return does.
            try? await Task.sleep(for: .milliseconds(150))
            ClipboardService.shared.pressReturn()
        }
```

Where the overlay's completed state is shown (`showCompleted(copiedToClipboard:)`), show the safety message instead when it applies:

```swift
        if stoppedBySafety {
            OverlayManager.shared.showError(message: "Stopped after 10 minutes")
        } else {
            OverlayManager.shared.showCompleted(copiedToClipboard: didCopyToClipboard)
        }
        stoppedBySafety = false
```

(Read the existing code around `showCompleted` and keep its condition; only the call is wrapped.) At the very end, before `sessionState = .idle`, add `sessionContext = nil`. Every early `return` path in the function (too short, timeout, failure, no audio) already resets state; add `safetyStopTask?.cancel()` is covered by the top of the function.

In `applicationDidFinishLaunching`, after `HistoryStore.shared.load()`:

```swift
        VocabularyStore.shared.load()
        ModeStore.shared.load()
```

- [ ] **Step 5: Build, run the suite, commit**

```bash
xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests 2>&1 | grep -E "error:|warning: .*(AppDelegate|Overlay|Clipboard|TranscriptionService)|\*\* TEST" | tail -5
git add app/justscribe/AppDelegate.swift app/justscribe/Services/ClipboardService.swift app/justscribe/Managers/OverlayManager.swift app/justscribe/Services/TranscriptionService.swift
git commit -m "Press the shortcut to start and stop, say the commands, and get your words and the app's mode applied to every dictation"
```

Expected: `** TEST SUCCEEDED **`, no new warnings.

---

### Task 8: Settings — Clean-up with Modes, and Vocabulary

**Files:**
- Rename: `app/justscribe/Views/Settings/Sections/GrammarCorrectionSettingsSection.swift` → `CleanUpSettingsSection.swift` (`git mv`)
- Create: `app/justscribe/Views/Settings/Components/ModeEditor.swift`, `app/justscribe/Views/Settings/Sections/VocabularySettingsSection.swift`
- Modify: `app/justscribe/Views/Settings/SettingsView.swift`

**Interfaces:**
- Consumes: `ModeStore.shared`, `VocabularyStore.shared`, `DictationMode`, `VocabularyEntry`, `ToggleSettingsRow`, `SettingsSectionContainer`, `.buttonStyle(.pill)`.

- [ ] **Step 1: Clean-up section**

`git mv` the file and rename the struct to `CleanUpSettingsSection`. Title `"Clean-up"`; the switch row becomes title `"Clean Up Text"`, subtitle `"Fix grammar, spelling and punctuation, or follow the instructions of the mode for the app you dictate into"`. Below the backend rows (inside the `if settings.grammarCorrectionEnabled`), add the Modes list:

```swift
                    Divider()
                    ModesList(store: ModeStore.shared)
```

Add at the bottom of the file:

```swift
private struct ModesList: View {
    let store: ModeStore
    @State private var editing: DictationMode?
    @State private var isAdding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Modes").font(.body)
                Spacer()
                Button("Add Mode…") { isAdding = true }.buttonStyle(.pillSmall)
            }
            Text("The app in front when you press the shortcut picks the mode; Default covers the rest.")
                .font(.caption).foregroundStyle(.secondary)
            if store.fileWasSetAside {
                Text("A damaged modes file was set aside; modes started again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(store.modes) { mode in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode.name)
                        Text(mode.isDefault ? "All other apps" : (mode.appBundleIDs.isEmpty ? "No apps yet" : appNames(mode.appBundleIDs)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !mode.cleanUp { Text("Raw").font(.caption).foregroundStyle(.secondary) }
                    Button("Edit") { editing = mode }.buttonStyle(.pillSmall)
                }
                .padding(.vertical, 2)
            }
        }
        .sheet(item: $editing) { mode in ModeEditor(store: store, mode: mode) }
        .sheet(isPresented: $isAdding) {
            ModeEditor(store: store, mode: DictationMode(id: UUID(), name: "", instructions: "", cleanUp: true, appBundleIDs: []), isNew: true)
        }
    }

    private func appNames(_ ids: [String]) -> String {
        ids.map { ModeEditor.displayName(forBundleID: $0) }.joined(separator: ", ")
    }
}
```

- [ ] **Step 2: `ModeEditor.swift`**

```swift
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The sheet that edits one mode: name, instructions, clean-up switch and the apps it applies to.
struct ModeEditor: View {
    let store: ModeStore
    @State var mode: DictationMode
    var isNew = false
    @Environment(\.dismiss) private var dismiss
    @State private var isPickingRunningApp = false

    init(store: ModeStore, mode: DictationMode, isNew: Bool = false) {
        self.store = store
        self._mode = State(initialValue: mode)
        self.isNew = isNew
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "New Mode" : "Edit Mode").font(.headline)

            TextField("Name", text: $mode.name)
                .textFieldStyle(.roundedBorder)
                .disabled(mode.isDefault)

            Toggle("Clean up text", isOn: $mode.cleanUp)
            Text(mode.cleanUp ? "The clean-up model follows these instructions:" : "Text is inserted as dictated, after voice commands and vocabulary.")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $mode.instructions)
                .font(.body)
                .frame(minHeight: 90)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                .disabled(!mode.cleanUp)
                .opacity(mode.cleanUp ? 1 : 0.5)
            if mode.isDefault {
                Button("Reset to Standard Instructions") { mode.instructions = DictationMode.defaultInstructions }
                    .buttonStyle(.pillSmall)
            }

            if !mode.isDefault {
                Text("Apps").font(.body)
                if mode.appBundleIDs.isEmpty {
                    Text("Add the apps this mode applies to.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(mode.appBundleIDs, id: \.self) { id in
                    HStack {
                        if let icon = Self.icon(forBundleID: id) { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
                        Text(Self.displayName(forBundleID: id))
                        Spacer()
                        Button { mode.appBundleIDs.removeAll { $0 == id } } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Menu("Add Running App") {
                        ForEach(Self.runningApps(), id: \.bundleIdentifier) { app in
                            Button(app.localizedName ?? app.bundleIdentifier ?? "App") {
                                if let id = app.bundleIdentifier, !mode.appBundleIDs.contains(id) { mode.appBundleIDs.append(id) }
                            }
                        }
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    Button("Other…") { pickApp() }.buttonStyle(.pillSmall)
                }
            }

            HStack {
                if !mode.isDefault && !isNew {
                    Button("Delete Mode", role: .destructive) { store.delete(mode.id); dismiss() }.buttonStyle(.pill)
                }
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.pill)
                Button(isNew ? "Add" : "Save") {
                    if isNew { store.add(mode) } else { store.update(mode) }
                    dismiss()
                }
                .buttonStyle(.pill)
                .disabled(mode.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        if !mode.appBundleIDs.contains(id) { mode.appBundleIDs.append(id) }
    }

    static func runningApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    static func displayName(forBundleID id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func icon(forBundleID id: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}
```

- [ ] **Step 3: `VocabularySettingsSection.swift`**

```swift
import AppKit
import SwiftUI

struct VocabularySettingsSection: View {
    private var store: VocabularyStore { .shared }
    @State private var newText = ""
    @State private var newForms = ""
    @State private var editingID: UUID?
    @State private var editText = ""
    @State private var editForms = ""
    @State private var importNote: String?

    var body: some View {
        SettingsSectionContainer(title: "Vocabulary") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Names and words to spell exactly as you write them. Add how the model tends to hear them to make a match certain.")
                    .font(.caption).foregroundStyle(.secondary)
                if store.fileWasSetAside {
                    Text("A damaged vocabulary file was set aside; the list started again.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    TextField("Text, e.g. SwiftUI", text: $newText).textFieldStyle(.roundedBorder)
                    TextField("Also heard as (comma-separated)", text: $newForms).textFieldStyle(.roundedBorder)
                    Button("Add") { add() }.buttonStyle(.pillSmall)
                        .disabled(newText.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                ForEach(store.entries) { entry in
                    if editingID == entry.id {
                        HStack(spacing: 8) {
                            TextField("Text", text: $editText).textFieldStyle(.roundedBorder)
                            TextField("Also heard as", text: $editForms).textFieldStyle(.roundedBorder)
                            Button("Save") {
                                var e = entry; e.text = editText; e.heardAs = Self.forms(editForms)
                                store.update(e); editingID = nil
                            }.buttonStyle(.pillSmall)
                            Button("Cancel") { editingID = nil }.buttonStyle(.pillSmall)
                        }
                    } else {
                        HStack(spacing: 8) {
                            Text(entry.text)
                            if !entry.heardAs.isEmpty {
                                Text("heard as " + entry.heardAs.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Edit") { editingID = entry.id; editText = entry.text; editForms = entry.heardAs.joined(separator: ", ") }
                                .buttonStyle(.pillSmall)
                            Button { store.delete(entry.id) } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }

                Divider()
                HStack {
                    Text(store.entries.count == 1 ? "1 entry" : "\(store.entries.count) entries")
                        .font(.caption).foregroundStyle(.secondary)
                    if let importNote { Text(importNote).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Import from Clipboard") { importFromClipboard() }.buttonStyle(.pill)
                }
            }
        }
    }

    private func add() {
        store.add(text: newText, heardAs: Self.forms(newForms))
        newText = ""; newForms = ""
    }

    private func importFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else { importNote = "Nothing to import"; return }
        let added = store.importLines(text)
        importNote = added == 0 ? "Nothing new to import" : (added == 1 ? "Added 1 entry" : "Added \(added) entries")
    }

    private static func forms(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
```

- [ ] **Step 4: `SettingsView.swift`** — order: Model, Microphone, Shortcut, Indicator, Clean-up, Vocabulary, Appearance, Behavior, History, Updates, Support, Links. Replace `GrammarCorrectionSettingsSection(settings: settings)` with `CleanUpSettingsSection(settings: settings)` followed by `Divider()` and `VocabularySettingsSection()`; move the `UpdateSettingsSection()` block (with its `Divider()`) to after `HistorySettingsSection(settings: settings)`.

- [ ] **Step 5: Build, run the suite, commit**

```bash
xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests 2>&1 | grep -E "error:|warning: .*(Settings|Mode|Vocabulary)|\*\* TEST" | tail -5
git add -A app/justscribe/Views/Settings
git commit -m "Settings: Clean-up modes per app, and a Vocabulary list with import from the clipboard"
```

---

### Task 9: Vocabulary in file transcripts

**Files:**
- Modify: `app/justscribe/Services/FileTranscription/FileTranscriptionJob.swift`, `app/justscribe/Views/FileTranscription/FileTranscriptionModel.swift`
- Test: `app/justscribeTests/FileTranscriptionJobTests.swift` (one new test)

**Interfaces:**
- Consumes: `VocabularyMatcher.apply(words:…)`, `VocabularyStore.shared.entries`, `DictionaryWords.isWord`.
- Produces: `FileTranscriptionJob.init(..., vocabulary: [VocabularyEntry] = [], isDictionaryWord: @escaping (String) -> Bool = { DictionaryWords.isWord($0, language: nil) }, ...)`; `static func applyVocabulary(_ words: [TimedWord], entries:, isDictionaryWord:) -> [TimedWord]`.

- [ ] **Step 1: Write the failing test** — add to `FileTranscriptionJobTests` (read the file's fakes first and reuse them; the pure helper needs none):

```swift
    @Test func vocabularyMergesAMatchedRunIntoOneTimedWord() {
        let words = [
            TimedWord(text: " I", start: 0, end: 0.2), TimedWord(text: " like", start: 0.2, end: 0.5),
            TimedWord(text: " swift", start: 0.5, end: 0.8), TimedWord(text: " UI.", start: 0.8, end: 1.1),
        ]
        let entries = [VocabularyEntry(id: UUID(), text: "SwiftUI", heardAs: ["swift ui"], createdAt: Date())]
        let out = FileTranscriptionJob.applyVocabulary(words, entries: entries, isDictionaryWord: { _ in true })
        #expect(out.map(\.text) == [" I", " like", " SwiftUI."])
        #expect(out[2].start == 0.5 && out[2].end == 1.1)
        #expect(FileTranscriptionJob.applyVocabulary(words, entries: [], isDictionaryWord: { _ in true }) == words)
    }
```

- [ ] **Step 2: Run; it must fail to compile**

Run: `xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests/FileTranscriptionJobTests 2>&1 | grep -E "error:|\*\* TEST" | head`
Expected: `error: type 'FileTranscriptionJob' has no member 'applyVocabulary'`

- [ ] **Step 3: Implement**

In `FileTranscriptionJob`: two new stored properties `private let vocabulary: [VocabularyEntry]` and `private let isDictionaryWord: (String) -> Bool`, two init parameters with the defaults above (after `speakerProvider`), and:

```swift
    /// The user's vocabulary applied to a chunk's words; a run that became one entry is one word
    /// spanning the run's time.
    nonisolated static func applyVocabulary(_ words: [TimedWord], entries: [VocabularyEntry], isDictionaryWord: (String) -> Bool) -> [TimedWord] {
        guard !entries.isEmpty, !words.isEmpty else { return words }
        let fixed = VocabularyMatcher.apply(words: words.map(\.text), entries: entries, isDictionaryWord: isDictionaryWord)
        var out: [TimedWord] = []
        for (word, text) in zip(words, fixed) {
            if text.isEmpty, !word.text.isEmpty, let last = out.indices.last {
                out[last].end = max(out[last].end, word.end)
            } else {
                out.append(TimedWord(text: text, start: word.start, end: word.end))
            }
        }
        return out
    }
```

Where the chunk's words are appended (`words += chunkWords.map { … }`), wrap: `words += Self.applyVocabulary(chunkWords, entries: vocabulary, isDictionaryWord: isDictionaryWord).map { TimedWord(text: $0.text, start: $0.start + chunk.startSeconds, end: $0.end + chunk.startSeconds) }`.

In `FileTranscriptionModel`, where the job is created, pass `vocabulary: VocabularyStore.shared.entries`.

- [ ] **Step 4: Run the suite, commit**

```bash
xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests 2>&1 | grep -E "error:|\*\* TEST" | tail -3
git add app/justscribe/Services/FileTranscription/FileTranscriptionJob.swift app/justscribe/Views/FileTranscription/FileTranscriptionModel.swift app/justscribeTests/FileTranscriptionJobTests.swift
git commit -m "File transcripts spell your vocabulary right too"
```

---

### Task 10: Documentation, privacy page, and the maintainer's hand checks

**Files:**
- Modify: `CLAUDE.md`, `README.md`, `web/src/pages/privacy.md`, `web/src/pages/index.astro`, `web/public/llms.txt`, `web/src/pages/superwhisper-alternative.md`, `web/src/pages/wispr-flow-alternative.md`

- [ ] **Step 1: `CLAUDE.md`** — after the `### History` section:

```markdown
### Dictation pipeline: commands, vocabulary, modes

`Services/Dictation/DictationPipeline` turns the raw final transcript into the inserted text:
`VoiceCommandProcessor` (new line / paragraph, scratch that, stop recording, send; spoken
punctuation when on) → `VocabularyMatcher` ("heard as" forms, then sound-alikes on non-dictionary
words only — `DictionaryWords` wraps `NSSpellChecker`) → clean-up through
`GrammarCorrectionService.correctGrammar(_:instructions:language:)` with the mode's instructions
inside `GrammarPrompt.frame`. `AppDelegate` builds a `DictationContext` at key down (trigger,
frontmost app → `ModeStore.mode(forApp:)`, vocabulary, switches) and keeps it for the session;
`stopRecordingAndFinalize` calls the pipeline where grammar correction used to run and applies the
result through the existing `replaceTypedText` bookkeeping. `RecordingTrigger` (`hold` /
`pressToToggle`) is read at key down; press mode ignores key up, stops on the next press, on a
spoken "stop recording" seen in the streaming text, on an overlay click, and after a 10-minute
safety stop. Whisper gets the vocabulary as `promptTokens` (≤ 200). Vocabulary and modes live in
`vocabulary.json` / `modes.json` in the container through `JSONFile`; Default mode has a fixed UUID.
```

- [ ] **Step 2: `README.md`** — after the history bullet:

```markdown
- A vocabulary for the names and words it must spell right, spoken commands ("new line", "scratch that", "stop recording"), hold-to-record or press-to-toggle, and clean-up modes that follow the app you dictate into
```

- [ ] **Step 3: Website** — `privacy.md` "What is stored on your Mac": add "your vocabulary and dictation modes" to the list sentence. `index.astro` feature list: `<li><strong>Knows your words.</strong> A vocabulary for names and jargon, spoken commands, press-to-toggle recording, and clean-up modes per app — all on your Mac.</li>` after the history bullet. `llms.txt` key facts: "Vocabulary and modes: custom words with 'heard as' forms, voice commands (new line, scratch that, stop recording, send), hold or press-to-toggle recording, clean-up instructions per app; stored on the Mac." In `superwhisper-alternative.md` and `wispr-flow-alternative.md`, update the "Text clean-up" row for JustScribe to "On-device clean-up with your own instructions per app, plus a vocabulary and voice commands".

- [ ] **Step 4: Verify and commit**

```bash
(cd web && npm run build >/dev/null && npm run check:dist | tail -1)
xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests 2>&1 | grep -E "\*\* TEST" | tail -1
git add CLAUDE.md README.md web/src/pages/privacy.md web/src/pages/index.astro web/public/llms.txt web/src/pages/superwhisper-alternative.md web/src/pages/wispr-flow-alternative.md
git commit -m "docs: vocabulary, voice commands, press-to-toggle and modes in the guide, README and website"
```

- [ ] **Step 5: Hand checks (maintainer, running the branch from Xcode)**

1. Hold mode unchanged: hold, speak, release → text as before. Switch to press mode: press, speak, press → text; the overlay says "Press the shortcut to stop"; clicking the overlay stops; say "stop recording" → stops ~2 s later; lower `safetyStop` to 15 s in a debug build and confirm "Stopped after 15 seconds" behaviour.
2. Switch the trigger in Settings while a press-mode recording runs: the next press still stops it.
3. Voice commands: "First point. New line. Second point", "Buy eggs scratch that buy milk", "Thanks. Send" in a chat app (message is sent), "I'll send" (left alone). Turn commands off → phrases are typed literally. Spoken punctuation on → "hello comma world period".
4. Vocabulary: add "Quassum" and "SwiftUI = swift ui"; dictate both with Parakeet and with a Whisper model; check a file transcript spells them too. Import three lines from the clipboard.
5. Modes: a mode "Email" bound to Mail with "Formal, British spelling"; a raw mode bound to Terminal (clean-up off); dictate into Mail, Terminal and Notes with Apple Intelligence and with Llama; the overlay shows "Email" in Mail.
6. Settings sections in the new order; Clean-up switch off → modes hidden, no model used; Default mode's instructions edited and reset.
