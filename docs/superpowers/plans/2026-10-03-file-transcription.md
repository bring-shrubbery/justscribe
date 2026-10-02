# File Transcription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A "Transcribe File…" window that turns an audio or video file into a transcript with timestamps and, optionally, speaker labels, entirely on the Mac.

**Architecture:** A file is decoded to 16 kHz mono and cut into 20–30 s chunks at quiet points; each chunk goes through the speech model already loaded for dictation and comes back as timed words; an optional first pass with FluidAudio's offline diarizer says who spoke when; a pure builder merges the two into paragraphs. A job object drives one file and yields to dictation between chunks. The pure parts (chunker, word assembly, transcript builder) hold no models and carry the tests.

**Tech Stack:** Swift (language mode 5, default actor isolation MainActor), SwiftUI + AppKit, AVFoundation, FluidAudio 0.14.5 (`AsrManager`, `OfflineDiarizerManager`), WhisperKit 0.15.0, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-03-file-transcription-design.md`

## Global Constraints

- Branch `file-transcription`. Never commit to `main`, never push: every code commit on `main` is released to users.
- Commit after each task. Commit subjects on this branch are squashed into one user-facing line at merge, so write them plainly; end each message with the `Co-Authored-By` trailer your session specifies.
- Build: `xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -configuration Debug build`. Unit tests: `xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests`. One test type: append `/<TypeName>`. The app target must build and all unit tests pass at the end of every task. Builds take minutes; SourceKit diagnostics are unreliable here, trust only `xcodebuild`.
- New files under `app/justscribe/` and `app/justscribeTests/` are picked up automatically. Never edit `project.pbxproj`. Never stage anything under `xcuserdata/`.
- The app target's default actor isolation is **MainActor**. Types that must be usable off the main actor or from tests without hopping are declared `nonisolated` (the pure value types and helpers in this plan say so). The test target has no default isolation: mark a test type `@MainActor` when it touches main-actor code.
- Every new Swift file starts with the project's GPL-3.0 header, with its own file name on the second line and the target name (`justscribe` or `justscribeTests`) on the third:

```swift
//
//  <FileName>.swift
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
```

  Code blocks in this plan omit the header; add it.
- Exact values from the spec: sample rate 16 000 Hz mono `Float`; chunks 20–30 s, cut at the quietest 100 ms window in the last 10 s; paragraph break on speaker change, on a pause ≥ 1.5 s, at a sentence end (`.`, `?`, `!`) once the paragraph is ≥ 60 s long, and at 90 s regardless; timestamp `[HH:MM:SS]` rounded down; speakers numbered from 1 by first appearance, labels dropped when there are fewer than two speakers; dictation polled every 200 ms; window 560×520; UserDefaults key `fileTranscription.identifySpeakers`; speaker count 1…10.
- Nothing about a file is persisted: no transcript, no path, no history.
- Do not launch the app from a subagent (the maintainer's installed copy shares the bundle ID and global hotkey). Hand checks are listed in Task 8 for the maintainer.

## Review Focus

1. **A language written without spaces (Chinese, Japanese)** — words must not gain spaces between them. Whisper's word pieces carry their own leading space or none; the transcript is built by concatenation, not by joining with spaces. Pinned in Task 1.
2. **A word with no speaker turn over it** (speech the diarizer missed, or a gap between turns) — it goes to the nearest turn in time rather than starting an unlabelled paragraph in the middle of a labelled transcript. Pinned in Task 1.
3. **A file shorter than one chunk, and an empty or silent file** — one chunk, or none, without a crash or a division by zero in progress; a silent file ends as "No speech was found in this file". Pinned in Tasks 2 and 5.
4. **Pressing the dictation shortcut during a file job** — the job must not call the model while dictation is active, and must resume after. Pinned in Task 5; the in-flight-chunk wait is checked by hand in Task 8.
5. **The model is switched or unloaded mid-job** — the job stops with the text so far instead of crashing on a nil model or mixing two models' output. Pinned in Task 5.

---

### Task 1: Timed text types and the transcript builder

**Files:**
- Create: `app/justscribe/Services/FileTranscription/TimedText.swift`
- Create: `app/justscribe/Services/FileTranscription/TranscriptBuilder.swift`
- Test: `app/justscribeTests/TranscriptBuilderTests.swift`

**Interfaces:**
- Produces: `TimedWord`, `SpeakerTurn`, `TranscriptParagraph` (all `nonisolated`, `Equatable`, `Sendable`); `TranscriptBuilder.paragraphs(words:turns:) -> [TranscriptParagraph]`, `TranscriptBuilder.text(_:) -> String`, `TranscriptBuilder.timestamp(_:) -> String`.

- [ ] **Step 1: Write `TimedText.swift`**

```swift
import Foundation

/// A word, or a word-sized piece, with its place in the file in seconds.
/// `text` is as the model produced it: it begins with a space when the piece starts a new
/// word in a language that separates words with spaces, and has none otherwise, so pieces
/// are joined by concatenation.
nonisolated struct TimedWord: Equatable, Sendable {
    var text: String
    var start: Double
    var end: Double
}

/// Who spoke between two times, from the diarizer. `speaker` is the diarizer's own label.
nonisolated struct SpeakerTurn: Equatable, Sendable {
    var speaker: String
    var start: Double
    var end: Double
}

/// One paragraph of the transcript. `speaker` is 1-based, nil when speakers are not shown.
nonisolated struct TranscriptParagraph: Equatable, Sendable {
    var start: Double
    var speaker: Int?
    var text: String
}
```

- [ ] **Step 2: Write the failing tests `TranscriptBuilderTests.swift`**

```swift
import Testing
@testable import justscribe

struct TranscriptBuilderTests {

    private func words(_ items: [(String, Double, Double)]) -> [TimedWord] {
        items.map { TimedWord(text: $0.0, start: $0.1, end: $0.2) }
    }

    @Test func noWordsGiveNoParagraphs() {
        #expect(TranscriptBuilder.paragraphs(words: [], turns: []).isEmpty)
        #expect(TranscriptBuilder.text([]) == "")
    }

    @Test func withoutTurnsThereAreNoSpeakerLabels() {
        let result = TranscriptBuilder.paragraphs(
            words: words([(" Hello", 4.2, 4.6), (" there.", 4.7, 5.1)]), turns: [])
        #expect(result == [TranscriptParagraph(start: 4.2, speaker: nil, text: "Hello there.")])
    }

    @Test func aPauseOfOneAndAHalfSecondsStartsAParagraph() {
        let result = TranscriptBuilder.paragraphs(
            words: words([(" One", 0, 0.5), (" two", 0.5, 1.0), (" three", 2.5, 3.0), (" four", 4.25, 4.75)]),
            turns: [])
        // 1.0 → 2.5 is exactly 1.5 s: a break. 3.0 → 4.25 is 1.25 s: not a break.
        // (The times are exact in binary, so the comparison is not at the mercy of rounding.)
        #expect(result.map(\.text) == ["One two", "three four"])
        #expect(result.map(\.start) == [0, 2.5])
    }

    @Test func aSpeakerChangeStartsAParagraphAndSpeakersAreNumberedByFirstAppearance() {
        let turns = [
            SpeakerTurn(speaker: "S7", start: 0, end: 2),
            SpeakerTurn(speaker: "S2", start: 2, end: 4),
            SpeakerTurn(speaker: "S7", start: 4, end: 6),
        ]
        let result = TranscriptBuilder.paragraphs(
            words: words([(" Hi", 0.2, 0.5), (" Yes", 2.1, 2.4), (" Good", 4.1, 4.5)]), turns: turns)
        #expect(result.map(\.speaker) == [1, 2, 1])
    }

    @Test func aWordGoesToTheTurnItOverlapsMost() {
        let turns = [SpeakerTurn(speaker: "A", start: 0, end: 1.0), SpeakerTurn(speaker: "B", start: 1.0, end: 5)]
        // 0.8–1.4: 0.2 s with A, 0.4 s with B.
        let result = TranscriptBuilder.paragraphs(
            words: words([(" first", 0.1, 0.5), (" second", 0.8, 1.4)]), turns: turns)
        #expect(result.map(\.speaker) == [1, 2])
    }

    @Test func aWordInAGapGoesToTheNearestTurn() {
        let turns = [SpeakerTurn(speaker: "A", start: 0, end: 1), SpeakerTurn(speaker: "B", start: 5, end: 9)]
        // 4.2–4.6 touches neither; B (0.4 s away) is nearer than A (3.2 s away).
        let result = TranscriptBuilder.paragraphs(
            words: words([(" early", 0.2, 0.6), (" late", 4.2, 4.6)]), turns: turns)
        #expect(result.map(\.speaker) == [1, 2])
    }

    @Test func aSingleSpeakerDropsTheLabels() {
        let turns = [SpeakerTurn(speaker: "A", start: 0, end: 3), SpeakerTurn(speaker: "A", start: 3, end: 6)]
        let result = TranscriptBuilder.paragraphs(words: words([(" Just", 0.1, 0.4), (" me", 0.5, 0.8)]), turns: turns)
        #expect(result == [TranscriptParagraph(start: 0.1, speaker: nil, text: "Just me")])
    }

    @Test func aLongRunBreaksAtTheFirstSentenceEndAfterSixtySeconds() {
        // One word per second, no pauses; sentence ends at t=30 and t=64.
        var items: [(String, Double, Double)] = []
        for second in 0..<80 {
            let text = (second == 30 || second == 64) ? " end." : " word"
            items.append((text, Double(second), Double(second) + 0.9))
        }
        let result = TranscriptBuilder.paragraphs(words: words(items), turns: [])
        #expect(result.count == 2)
        #expect(result[1].start == 65)   // the break follows the sentence that ends at 64.9
    }

    @Test func aRunWithoutSentenceEndsBreaksAtNinetySeconds() {
        let items = (0..<100).map { (" word", Double($0), Double($0) + 0.9) }
        let result = TranscriptBuilder.paragraphs(words: words(items), turns: [])
        #expect(result.count == 2)
        #expect(result[1].start == 90)
    }

    @Test func piecesAreConcatenatedSoUnspacedLanguagesStayUnspaced() {
        let result = TranscriptBuilder.paragraphs(
            words: words([("こん", 0, 0.3), ("にちは", 0.3, 0.8), ("。", 0.8, 0.9)]), turns: [])
        #expect(result.map(\.text) == ["こんにちは。"])
    }

    @Test func textFormatsTimestampsSpeakersAndBlankLines() {
        let text = TranscriptBuilder.text([
            TranscriptParagraph(start: 4.9, speaker: 1, text: "So the first thing."),
            TranscriptParagraph(start: 3725.2, speaker: 2, text: "Right."),
        ])
        #expect(text == "[00:00:04] Speaker 1\nSo the first thing.\n\n[01:02:05] Speaker 2\nRight.")
    }

    @Test func textWithoutSpeakersHasOnlyTheTime() {
        let text = TranscriptBuilder.text([TranscriptParagraph(start: 61, speaker: nil, text: "Hello.")])
        #expect(text == "[00:01:01]\nHello.")
    }

    @Test func earlierParagraphsDoNotChangeAsWordsArrive() {
        let turns = [SpeakerTurn(speaker: "A", start: 0, end: 10), SpeakerTurn(speaker: "B", start: 10, end: 20)]
        let all = words([(" One", 1, 1.4), (" two.", 1.5, 2), (" Three", 11, 11.4), (" four", 11.5, 12)])
        let partial = TranscriptBuilder.paragraphs(words: Array(all.prefix(3)), turns: turns)
        let full = TranscriptBuilder.paragraphs(words: all, turns: turns)
        #expect(partial.count == 2 && full.count == 2)
        #expect(partial[0] == full[0])
        #expect(partial[1].speaker == 2)   // labelled from the turns, though only speaker 1 had spoken before
    }
}
```

- [ ] **Step 3: Run; it must fail to compile**

Run: `xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests/TranscriptBuilderTests 2>&1 | grep -E "error:|\*\* TEST" | head`
Expected: `error: cannot find 'TranscriptBuilder' in scope`

- [ ] **Step 4: Write `TranscriptBuilder.swift`**

```swift
import Foundation

/// Turns timed words and speaker turns into the paragraphs of a transcript. Pure: no models,
/// no clock. Safe to call again with more words: paragraphs already produced do not change,
/// except that the last one may grow, because speaker numbers come from the turns (which
/// are complete before transcription starts), not from the words seen so far.
nonisolated enum TranscriptBuilder {
    /// A silence this long between two words starts a new paragraph.
    static let pauseBreak = 1.5
    /// Once a paragraph is this long it ends at the next sentence end.
    static let softLimit = 60.0
    /// A paragraph never runs longer than this.
    static let hardLimit = 90.0

    static func paragraphs(words: [TimedWord], turns: [SpeakerTurn]) -> [TranscriptParagraph] {
        let numbers = speakerNumbers(turns)
        let labelled = numbers.count >= 2
        var result: [TranscriptParagraph] = []
        var previous: TimedWord?
        var previousSpeaker: Int?

        for word in words where !word.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let speaker = labelled ? speaker(for: word, in: turns).flatMap { numbers[$0] } : nil
            var startsParagraph = result.isEmpty
            if let previous, let current = result.last {
                let length = previous.end - current.start
                let endsSentence = previous.text.trimmingCharacters(in: .whitespaces).last.map { ".?!".contains($0) } ?? false
                startsParagraph = speaker != previousSpeaker
                    || word.start - previous.end >= pauseBreak
                    || word.end - current.start > hardLimit
                    || (length >= softLimit && endsSentence)
            }
            if startsParagraph {
                result.append(TranscriptParagraph(start: word.start, speaker: speaker, text: word.text))
            } else {
                result[result.count - 1].text += word.text
            }
            previous = word
            previousSpeaker = speaker
        }
        return result.map { paragraph in
            var tidy = paragraph
            tidy.text = paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return tidy
        }
    }

    static func text(_ paragraphs: [TranscriptParagraph]) -> String {
        paragraphs.map { paragraph in
            let label = paragraph.speaker.map { " Speaker \($0)" } ?? ""
            return "[\(timestamp(paragraph.start))]\(label)\n\(paragraph.text)"
        }.joined(separator: "\n\n")
    }

    /// `3725.9` → `01:02:05` (rounded down).
    static func timestamp(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// The diarizer's labels numbered 1, 2, … in order of first appearance.
    private static func speakerNumbers(_ turns: [SpeakerTurn]) -> [String: Int] {
        var numbers: [String: Int] = [:]
        for turn in turns.sorted(by: { $0.start < $1.start }) where numbers[turn.speaker] == nil {
            numbers[turn.speaker] = numbers.count + 1
        }
        return numbers
    }

    /// The turn the word overlaps most; when it overlaps none, the turn nearest in time.
    private static func speaker(for word: TimedWord, in turns: [SpeakerTurn]) -> String? {
        var best: (speaker: String, overlap: Double, distance: Double)?
        for turn in turns {
            let overlap = max(0, min(word.end, turn.end) - max(word.start, turn.start))
            let distance = overlap > 0 ? 0 : max(turn.start - word.end, word.start - turn.end)
            if let current = best {
                let better = overlap > current.overlap || (overlap == current.overlap && distance < current.distance)
                if better { best = (turn.speaker, overlap, distance) }
            } else {
                best = (turn.speaker, overlap, distance)
            }
        }
        return best?.speaker
    }
}
```

- [ ] **Step 5: Run; all thirteen tests pass**

Run the Step 3 command. Expected: `** TEST SUCCEEDED **`. If `aLongRunBreaksAtTheFirstSentenceEndAfterSixtySeconds` or the 90 s case is off by one word, re-read the rule in Global Constraints: the sentence-end rule compares the length from the paragraph's start to the *previous* word's end; the 90 s rule asks whether adding the *current* word would take the paragraph past 90 s; either way the break happens *before* the current word.

- [ ] **Step 6: Commit**

```bash
git add app/justscribe/Services/FileTranscription app/justscribeTests/TranscriptBuilderTests.swift
git commit -m "Build transcript paragraphs from timed words and speaker turns"
```

---

### Task 2: Audio chunker

**Files:**
- Create: `app/justscribe/Services/FileTranscription/AudioChunker.swift`
- Test: `app/justscribeTests/AudioChunkerTests.swift`

**Interfaces:**
- Produces: `AudioChunk { samples: [Float]; startSeconds: Double }`; `AudioChunker` with `mutating func append(_ samples: [Float]) -> [AudioChunk]` and `mutating func finish() -> AudioChunk?`; `AudioChunker.sampleRate == 16_000`.

- [ ] **Step 1: Write the failing tests `AudioChunkerTests.swift`**

```swift
import Testing
@testable import justscribe

struct AudioChunkerTests {
    private let rate = AudioChunker.sampleRate

    /// `seconds` of a constant-amplitude tone, so every 100 ms window is equally loud.
    private func tone(seconds: Double, amplitude: Float = 0.5) -> [Float] {
        (0..<Int(seconds * Double(rate))).map { $0 % 2 == 0 ? amplitude : -amplitude }
    }

    private func allChunks(_ input: [Float], feed: Int = 4_096) -> [AudioChunk] {
        var chunker = AudioChunker()
        var chunks: [AudioChunk] = []
        var index = 0
        while index < input.count {
            let next = min(index + feed, input.count)
            chunks += chunker.append(Array(input[index..<next]))
            index = next
        }
        if let last = chunker.finish() { chunks.append(last) }
        return chunks
    }

    @Test func emptyInputYieldsNoChunks() {
        #expect(allChunks([]).isEmpty)
    }

    @Test func aClipShorterThanTwentySecondsIsOneChunk() {
        let input = tone(seconds: 7.5)
        let chunks = allChunks(input)
        #expect(chunks.count == 1)
        #expect(chunks[0].samples == input)
        #expect(chunks[0].startSeconds == 0)
    }

    @Test func chunksConcatenateToTheInput() {
        let input = tone(seconds: 95.3)
        #expect(allChunks(input).flatMap(\.samples) == input)
    }

    @Test func everyChunkButTheLastIsTwentyToThirtySeconds() {
        let chunks = allChunks(tone(seconds: 200))
        #expect(chunks.count >= 2)
        for chunk in chunks.dropLast() {
            #expect(chunk.samples.count >= 20 * rate)
            #expect(chunk.samples.count <= 30 * rate)
        }
        #expect(chunks.last.map { !$0.samples.isEmpty } == true)
    }

    @Test func startOffsetsFollowTheSamplesBefore() {
        let chunks = allChunks(tone(seconds: 70))
        var samplesBefore = 0
        for chunk in chunks {
            #expect(chunk.startSeconds == Double(samplesBefore) / Double(rate))
            samplesBefore += chunk.samples.count
        }
    }

    @Test func theCutLandsInAPlantedSilence() {
        // 40 s of tone with 300 ms of silence starting at 24.0 s.
        var input = tone(seconds: 40)
        let silenceStart = 24 * rate
        for index in silenceStart..<(silenceStart + 3 * rate / 10) { input[index] = 0 }
        let first = allChunks(input)[0]
        #expect(first.samples.count >= silenceStart)
        #expect(first.samples.count <= silenceStart + 3 * rate / 10)
    }

    @Test func theResultDoesNotDependOnHowTheInputArrives() {
        let input = tone(seconds: 65)
        #expect(allChunks(input, feed: 1_000).map(\.samples.count) == allChunks(input, feed: 100_000).map(\.samples.count))
    }
}
```

- [ ] **Step 2: Run; it must fail to compile**

Run: `xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests/AudioChunkerTests 2>&1 | grep -E "error:|\*\* TEST" | head`
Expected: `error: cannot find 'AudioChunker' in scope`

- [ ] **Step 3: Write `AudioChunker.swift`**

```swift
import Foundation

/// A stretch of 16 kHz mono audio and where it starts in the file.
nonisolated struct AudioChunk: Equatable, Sendable {
    var samples: [Float]
    var startSeconds: Double
}

/// Cuts a stream of samples into chunks of 20 to 30 seconds for the speech model. Each cut
/// is placed in the quietest 100 ms of the last ten seconds, so a word is rarely split.
/// The chunks concatenated are exactly the input.
nonisolated struct AudioChunker {
    static let sampleRate = 16_000
    private static let minimum = 20 * sampleRate
    private static let maximum = 30 * sampleRate
    private static let window = sampleRate / 10

    private var pending: [Float] = []
    private var emitted = 0

    /// Adds samples and returns every chunk that is now complete.
    mutating func append(_ samples: [Float]) -> [AudioChunk] {
        pending += samples
        var chunks: [AudioChunk] = []
        while pending.count >= Self.maximum {
            chunks.append(take(Self.cutIndex(in: pending)))
        }
        return chunks
    }

    /// The remainder, once the input has ended; nil when nothing is left.
    mutating func finish() -> AudioChunk? {
        pending.isEmpty ? nil : take(pending.count)
    }

    private mutating func take(_ count: Int) -> AudioChunk {
        let chunk = AudioChunk(samples: Array(pending.prefix(count)), startSeconds: Double(emitted) / Double(Self.sampleRate))
        pending.removeFirst(count)
        emitted += count
        return chunk
    }

    /// The middle of the quietest window between 20 and 30 seconds; `samples` holds at least 30 s.
    private static func cutIndex(in samples: [Float]) -> Int {
        var quietest = minimum
        var lowest = Float.greatestFiniteMagnitude
        var start = minimum
        while start + window <= maximum {
            var energy: Float = 0
            for index in start..<(start + window) { energy += samples[index] * samples[index] }
            if energy < lowest {
                lowest = energy
                quietest = start
            }
            start += window
        }
        return quietest + window / 2
    }
}
```

- [ ] **Step 4: Run; all seven tests pass**

Run the Step 2 command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add app/justscribe/Services/FileTranscription/AudioChunker.swift app/justscribeTests/AudioChunkerTests.swift
git commit -m "Cut file audio into chunks at quiet points"
```

---

### Task 3: Timed transcription in `TranscriptionService`

**Files:**
- Create: `app/justscribe/Services/FileTranscription/TimedWordAssembler.swift`
- Create: `app/justscribe/Services/FileTranscription/InferenceGate.swift`
- Modify: `app/justscribe/Services/TranscriptionService.swift`
- Test: `app/justscribeTests/TimedWordAssemblerTests.swift`, `app/justscribeTests/InferenceGateTests.swift`

**Interfaces:**
- Consumes: `TimedWord` (Task 1).
- Produces:
  - `TimedWordAssembler.words(fromTokens: [TimedWord]) -> [TimedWord]`
  - `InferenceGate` with `func run<T>(_ body: () async throws -> T) async rethrows -> T`
  - `protocol TimedTranscribing: AnyObject` (main-actor): `var isModelLoaded: Bool { get }`, `var modelGeneration: Int { get }`, `func transcribeTimed(_ buffer: [Float], language: String?) async throws -> [TimedWord]`; `TranscriptionService` conforms.

- [ ] **Step 1: Write the failing tests**

`TimedWordAssemblerTests.swift`:

```swift
import Testing
@testable import justscribe

struct TimedWordAssemblerTests {
    private func token(_ text: String, _ start: Double, _ end: Double) -> TimedWord {
        TimedWord(text: text, start: start, end: end)
    }

    @Test func noTokensGiveNoWords() {
        #expect(TimedWordAssembler.words(fromTokens: []).isEmpty)
    }

    @Test func tokensWithoutALeadingSpaceContinueTheWord() {
        let words = TimedWordAssembler.words(fromTokens: [
            token(" trans", 0.0, 0.2), token("crip", 0.2, 0.4), token("tion", 0.4, 0.7), token(" works", 0.8, 1.2),
        ])
        #expect(words == [token(" transcription", 0.0, 0.7), token(" works", 0.8, 1.2)])
    }

    @Test func theSentencePieceMarkerCountsAsALeadingSpace() {
        let words = TimedWordAssembler.words(fromTokens: [token("▁Hello", 0, 0.3), token("▁there", 0.4, 0.7)])
        #expect(words.map(\.text) == [" Hello", " there"])
    }

    @Test func theFirstTokenStartsAWordEvenWithoutASpace() {
        let words = TimedWordAssembler.words(fromTokens: [token("Hel", 0, 0.2), token("lo", 0.2, 0.4)])
        #expect(words == [token(" Hello", 0, 0.4)])
    }

    @Test func punctuationAttachesToTheWordBeforeIt() {
        let words = TimedWordAssembler.words(fromTokens: [token(" Yes", 0, 0.3), token(".", 0.3, 0.35), token(" No", 0.6, 0.8)])
        #expect(words.map(\.text) == [" Yes.", " No"])
    }

    @Test func emptyTokensAreSkipped() {
        let words = TimedWordAssembler.words(fromTokens: [token(" a", 0, 0.1), token("", 0.1, 0.2), token(" b", 0.3, 0.4)])
        #expect(words.map(\.text) == [" a", " b"])
    }
}
```

`InferenceGateTests.swift`:

```swift
import Testing
@testable import justscribe

@MainActor
struct InferenceGateTests {

    @Test func bodiesNeverOverlapAndRunInArrivalOrder() async {
        let gate = InferenceGate()
        var running = 0
        var maxRunning = 0
        var order: [Int] = []

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<5 {
                group.addTask { @MainActor in
                    await gate.run {
                        running += 1
                        maxRunning = max(maxRunning, running)
                        order.append(index)
                        try? await Task.sleep(for: .milliseconds(20))
                        running -= 1
                    }
                }
                // Let each task reach the gate before the next is added, so arrival order is 0…4.
                try? await Task.sleep(for: .milliseconds(2))
            }
        }
        #expect(maxRunning == 1)
        #expect(order == [0, 1, 2, 3, 4])
    }

    @Test func aThrowingBodyReleasesTheGate() async {
        struct Boom: Error {}
        let gate = InferenceGate()
        await #expect(throws: Boom.self) { try await gate.run { throw Boom() } }
        let value = await gate.run { 7 }
        #expect(value == 7)
    }
}
```

- [ ] **Step 2: Run; they must fail to compile**

Run: `xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests/TimedWordAssemblerTests -only-testing:justscribeTests/InferenceGateTests 2>&1 | grep -E "error:|\*\* TEST" | head`
Expected: `error: cannot find 'TimedWordAssembler' in scope` (and `InferenceGate`).

- [ ] **Step 3: Write `TimedWordAssembler.swift`**

```swift
import Foundation

/// Joins a speech model's sub-word tokens into words. Parakeet reports a time for every
/// token; a token that begins with a space (or the SentencePiece marker) starts a new word,
/// and any other token continues the word before it.
nonisolated enum TimedWordAssembler {
    static func words(fromTokens tokens: [TimedWord]) -> [TimedWord] {
        var words: [TimedWord] = []
        for token in tokens {
            let text = token.text.replacingOccurrences(of: "▁", with: " ")
            if text.isEmpty { continue }
            if text.hasPrefix(" ") || words.isEmpty {
                words.append(TimedWord(text: text.hasPrefix(" ") ? text : " " + text, start: token.start, end: token.end))
            } else {
                words[words.count - 1].text += text
                words[words.count - 1].end = token.end
            }
        }
        return words
    }
}
```

- [ ] **Step 4: Write `InferenceGate.swift`**

```swift
import Foundation

/// Lets one request at a time use the speech model. Dictation's live passes, its final pass
/// and file chunks all go through it, in the order they arrive, so the model never serves
/// two requests at once.
final class InferenceGate {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run<T>(_ body: () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await body()
    }

    private func acquire() async {
        if !busy {
            busy = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
```

(The type is main-actor isolated by the target's default; that is what makes `busy` and `waiters` safe without a lock.)

- [ ] **Step 5: Run the two test types; they pass**

Run the Step 2 command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Change `TranscriptionService.swift`**

Add, next to the other stored properties:

```swift
    /// Counts every model load and unload, so a long-running caller can tell the model changed.
    private(set) var modelGeneration = 0

    /// Serialises every use of the speech model (dictation and file chunks).
    private let gate = InferenceGate()
```

In `unloadModel()`, add `modelGeneration += 1` as its first line. (A load calls `unloadModel()` first, so loading also advances it.)

Wrap the two existing inference bodies in the gate. `transcribeWithWhisperKit` becomes:

```swift
    private func transcribeWithWhisperKit(buffer: [Float], language: String?) async throws -> String {
        try await gate.run {
            guard let whisperKit = whisperKit else {
                throw TranscriptionError.modelNotLoaded
            }

            var options = DecodingOptions()
            if let language = language, !language.isEmpty {
                options.language = language
            }

            let results = try await whisperKit.transcribe(audioArray: buffer, decodeOptions: options)
            return results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
```

and `transcribeWithFluidAudio` keeps its body, moved inside `try await gate.run { … }` the same way (the `guard` included, so the model is looked up after the wait).

Add the timed path after `processAudioBuffer`:

```swift
    // MARK: - Timed transcription (file transcription)

    /// Transcribes `buffer` and returns its words with times relative to the buffer's start.
    /// Unlike the dictation paths it leaves `state` and `currentTranscription` alone.
    func transcribeTimed(_ buffer: [Float], language: String?) async throws -> [TimedWord] {
        try await gate.run {
            switch loadedProvider {
            case .whisperKit:
                guard let whisperKit else { throw TranscriptionError.modelNotLoaded }
                var options = DecodingOptions()
                if let language, !language.isEmpty { options.language = language }
                options.wordTimestamps = true
                options.skipSpecialTokens = true
                let results = try await whisperKit.transcribe(audioArray: buffer, decodeOptions: options)
                return results.flatMap(\.segments).flatMap { segment -> [TimedWord] in
                    if let words = segment.words, !words.isEmpty {
                        return words.map { TimedWord(text: $0.word, start: Double($0.start), end: Double($0.end)) }
                    }
                    let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    return text.isEmpty ? [] : [TimedWord(text: " " + text, start: Double(segment.start), end: Double(segment.end))]
                }
            case .fluidAudio:
                guard let asrManager else { throw TranscriptionError.modelNotLoaded }
                var decoderState = try TdtDecoderState()
                let result = try await asrManager.transcribe(buffer, decoderState: &decoderState)
                if let timings = result.tokenTimings, !timings.isEmpty {
                    return TimedWordAssembler.words(
                        fromTokens: timings.map { TimedWord(text: $0.token, start: $0.startTime, end: $0.endTime) })
                }
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? [] : [TimedWord(text: " " + text, start: 0, end: Double(buffer.count) / 16_000)]
            case nil:
                throw TranscriptionError.modelNotLoaded
            }
        }
    }
```

At the end of the file, outside the class:

```swift
/// What a file job needs from the speech model; a protocol so tests can stand in for it.
protocol TimedTranscribing: AnyObject {
    var isModelLoaded: Bool { get }
    var modelGeneration: Int { get }
    func transcribeTimed(_ buffer: [Float], language: String?) async throws -> [TimedWord]
}

extension TranscriptionService: TimedTranscribing {}
```

If the compiler rejects `results.flatMap(\.segments)` because WhisperKit's result properties are wrapped, write `results.flatMap { $0.segments }`. If `asrManager.transcribe`'s token timing fields are named differently in the resolved FluidAudio version, read `ASR/Parakeet/AsrTypes.swift` in the package checkout (`TokenTiming`) and use its names; the contract is one `TimedWord` per token with the token's own text.

- [ ] **Step 7: Build and run the whole unit suite**

Run: `xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests 2>&1 | grep -E "error:|warning: .*TranscriptionService|\*\* TEST" | tail -5`
Expected: `** TEST SUCCEEDED **`, no new warnings from `TranscriptionService.swift`.

- [ ] **Step 8: Commit**

```bash
git add app/justscribe/Services app/justscribeTests/TimedWordAssemblerTests.swift app/justscribeTests/InferenceGateTests.swift
git commit -m "Return timed words from the speech model, one request at a time"
```

---

### Task 4: Audio file decoder

**Files:**
- Create: `app/justscribe/Services/FileTranscription/AudioFileDecoder.swift`
- Test: `app/justscribeTests/AudioFileDecoderTests.swift`

**Interfaces:**
- Produces:
  - `nonisolated protocol FileAudioSource: Sendable { var duration: Double { get }; func next() async throws -> [Float]? }`
  - `actor AudioFileDecoder: FileAudioSource` with `static func open(_ url: URL) async throws -> AudioFileDecoder`
  - `enum AudioFileError: Error, Equatable { case notReadable, noAudioTrack, protectedContent }` with `var message: String`

- [ ] **Step 1: Write the failing tests `AudioFileDecoderTests.swift`**

```swift
import AVFoundation
import Foundation
import Testing
@testable import justscribe

struct AudioFileDecoderTests {

    /// Writes `seconds` of a 440 Hz tone as a 44.1 kHz stereo WAV and returns its URL.
    private func makeWAV(seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("justscribe-\(UUID().uuidString).wav")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(seconds * 44_100)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        for channel in 0..<2 {
            let data = try #require(buffer.floatChannelData?[channel])
            for frame in 0..<Int(frames) { data[frame] = sinf(2 * .pi * 440 * Float(frame) / 44_100) * 0.5 }
        }
        try file.write(from: buffer)
        return url
    }

    private func readAll(_ decoder: AudioFileDecoder) async throws -> [Float] {
        var samples: [Float] = []
        while let next = try await decoder.next() { samples += next }
        return samples
    }

    @Test func aStereoFileDecodesToSixteenKilohertzMono() async throws {
        let url = try makeWAV(seconds: 3)
        defer { try? FileManager.default.removeItem(at: url) }
        let decoder = try await AudioFileDecoder.open(url)
        #expect(abs(decoder.duration - 3) < 0.05)
        let samples = try await readAll(decoder)
        #expect(abs(Double(samples.count) - 48_000) < 480)          // within 1%
        #expect((samples.map(abs).max() ?? 0) > 0.2)                // it is the tone, not silence
        #expect(try await decoder.next() == nil)                    // stays finished
    }

    @Test func aFileThatIsNotMediaIsNotReadable() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("justscribe-\(UUID().uuidString).txt")
        try "not audio".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: AudioFileError.notReadable) { _ = try await AudioFileDecoder.open(url) }
    }

    @Test func aMissingFileIsNotReadable() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("justscribe-missing-\(UUID().uuidString).m4a")
        await #expect(throws: AudioFileError.notReadable) { _ = try await AudioFileDecoder.open(url) }
    }

    @Test func everyErrorHasASentenceForTheWindow() {
        #expect(AudioFileError.notReadable.message == "JustScribe can't read this file")
        #expect(AudioFileError.noAudioTrack.message == "This file has no audio")
        #expect(AudioFileError.protectedContent.message == "This file is copy-protected and can't be transcribed")
    }
}
```

(A video file with no audio track is checked by hand in Task 8: producing one in a unit test needs a video encoder session, which is slow and flaky under the test host.)

- [ ] **Step 2: Run; it must fail to compile**

Run: `xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests/AudioFileDecoderTests 2>&1 | grep -E "error:|\*\* TEST" | head`
Expected: `error: cannot find 'AudioFileDecoder' in scope`

- [ ] **Step 3: Write `AudioFileDecoder.swift`**

```swift
import AVFoundation
import Foundation

/// A file's audio as a stream of 16 kHz mono samples; a protocol so tests can stand in for a file.
/// Not tied to the main actor: decoding happens off it.
nonisolated protocol FileAudioSource: Sendable {
    /// The length of the audio in seconds.
    var duration: Double { get }
    /// The next stretch of samples, nil once the file has ended.
    func next() async throws -> [Float]?
}

nonisolated enum AudioFileError: Error, Equatable {
    case notReadable
    case noAudioTrack
    case protectedContent

    var message: String {
        switch self {
        case .notReadable: "JustScribe can't read this file"
        case .noAudioTrack: "This file has no audio"
        case .protectedContent: "This file is copy-protected and can't be transcribed"
        }
    }
}

/// Decodes the first audio track of any file AVFoundation can read to 16 kHz mono floats,
/// one buffer at a time, so the length of the file does not decide how much memory is used.
actor AudioFileDecoder: FileAudioSource {
    nonisolated let duration: Double
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private var finished = false

    static func open(_ url: URL) async throws -> AudioFileDecoder {
        let asset = AVURLAsset(url: url)
        let tracks: [AVAssetTrack]
        let seconds: Double
        do {
            if try await asset.load(.hasProtectedContent) { throw AudioFileError.protectedContent }
            tracks = try await asset.loadTracks(withMediaType: .audio)
            seconds = try await asset.load(.duration).seconds
        } catch let error as AudioFileError {
            throw error
        } catch {
            throw AudioFileError.notReadable
        }
        guard let track = tracks.first else {
            // A readable asset with no audio track; anything AVFoundation cannot open at all threw above.
            let hasAnyTrack = ((try? await asset.load(.tracks)) ?? []).isEmpty == false
            throw hasAnyTrack ? AudioFileError.noAudioTrack : AudioFileError.notReadable
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        do {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { throw AudioFileError.notReadable }
            reader.add(output)
            guard reader.startReading() else { throw AudioFileError.notReadable }
            return AudioFileDecoder(reader: reader, output: output, duration: seconds.isFinite ? seconds : 0)
        } catch let error as AudioFileError {
            throw error
        } catch {
            throw AudioFileError.notReadable
        }
    }

    private init(reader: AVAssetReader, output: AVAssetReaderTrackOutput, duration: Double) {
        self.reader = reader
        self.output = output
        self.duration = duration
    }

    func next() async throws -> [Float]? {
        while !finished {
            guard let sampleBuffer = output.copyNextSampleBuffer() else {
                finished = true
                if reader.status == .failed { throw AudioFileError.notReadable }
                return nil
            }
            guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            if length == 0 { continue }
            var samples = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            let status = samples.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes.count, destination: bytes.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { throw AudioFileError.notReadable }
            return samples
        }
        return nil
    }
}
```

If the compiler objects to `AVAssetReader` or `AVAssetReaderTrackOutput` stored in an actor (they are not `Sendable`), mark the two properties `nonisolated(unsafe)`: they are created in `open` and then only touched from the actor.

- [ ] **Step 4: Run; all four tests pass**

Run the Step 2 command. Expected: `** TEST SUCCEEDED **`. If the missing-file or text-file case throws something other than `notReadable`, look at which `load` call threw and make sure it is inside the `do` that maps to `notReadable`.

- [ ] **Step 5: Commit**

```bash
git add app/justscribe/Services/FileTranscription/AudioFileDecoder.swift app/justscribeTests/AudioFileDecoderTests.swift
git commit -m "Decode audio and video files to the speech model's format"
```

---

### Task 5: The file transcription job

**Files:**
- Create: `app/justscribe/Services/FileTranscription/FileTranscriptionJob.swift`
- Test: `app/justscribeTests/FileTranscriptionJobTests.swift`

**Interfaces:**
- Consumes: `AudioChunker`, `AudioChunk` (Task 2); `TimedTranscribing` (Task 3); `FileAudioSource`, `AudioFileError` (Task 4); `TranscriptBuilder`, `TimedWord`, `SpeakerTurn`, `TranscriptParagraph` (Task 1).
- Produces:
  - `protocol DictationActivity: AnyObject { var isDictating: Bool { get } }`
  - `protocol SpeakerTurnProviding: AnyObject { func turns(for url: URL, speakerCount: Int?) async throws -> [SpeakerTurn] }`
  - `final class FileTranscriptionJob` (`@Observable`, main actor): `enum Phase: Equatable { idle, identifyingSpeakers, transcribing(Double), pausedForDictation(Double), finished, cancelled, failed(String) }`, `private(set) var phase`, `private(set) var paragraphs`, `var text: String`, `var isRunning: Bool`, `func start()`, `func cancel()`, `func run() async`.
  - `enum SpeakerRequest: Equatable { case none; case detect; case exactly(Int) }`
  - `FileTranscriptionJob.Message` string constants used by the view.

- [ ] **Step 1: Write the failing tests `FileTranscriptionJobTests.swift`**

```swift
import Foundation
import Testing
@testable import justscribe

/// Audio that is `seconds` long, handed out in one-second buffers of a steady tone.
private final class FakeSource: FileAudioSource, @unchecked Sendable {
    let duration: Double
    private var remaining: Int
    init(seconds: Int) {
        duration = Double(seconds)
        remaining = seconds
    }
    func next() async throws -> [Float]? {
        guard remaining > 0 else { return nil }
        remaining -= 1
        return (0..<16_000).map { $0 % 2 == 0 ? 0.5 : -0.5 }
    }
}

@MainActor
private final class FakeTranscriber: TimedTranscribing {
    var isModelLoaded = true
    var modelGeneration = 1
    var calls = 0
    var failOnCall: Int?
    var changeModelOnCall: Int?
    var wordsPerChunk: [[TimedWord]] = []
    var onCall: (() -> Void)?

    struct Boom: LocalizedError { var errorDescription: String? { "the model fell over" } }

    func transcribeTimed(_ buffer: [Float], language: String?) async throws -> [TimedWord] {
        calls += 1
        onCall?()
        if failOnCall == calls { throw Boom() }
        if changeModelOnCall == calls { modelGeneration += 1 }
        if calls <= wordsPerChunk.count { return wordsPerChunk[calls - 1] }
        return [TimedWord(text: " chunk\(calls).", start: 1, end: 2)]
    }
}

@MainActor
private final class FakeDictation: DictationActivity {
    var isDictating = false
}

@MainActor
private final class FakeSpeakers: SpeakerTurnProviding {
    var result: Result<[SpeakerTurn], Error> = .success([])
    var requested: Int??
    struct Boom: Error {}
    func turns(for url: URL, speakerCount: Int?) async throws -> [SpeakerTurn] {
        requested = .some(speakerCount)
        return try result.get()
    }
}

@MainActor
struct FileTranscriptionJobTests {
    private let url = URL(fileURLWithPath: "/tmp/interview.m4a")

    private func makeJob(
        seconds: Int, speakers: SpeakerRequest = .none,
        transcriber: FakeTranscriber = FakeTranscriber(), dictation: FakeDictation = FakeDictation(),
        provider: FakeSpeakers = FakeSpeakers(), open: (@Sendable (URL) async throws -> any FileAudioSource)? = nil
    ) -> FileTranscriptionJob {
        FileTranscriptionJob(
            url: url, language: "en", speakers: speakers,
            transcriber: transcriber, dictation: dictation, speakerProvider: provider,
            openSource: open ?? { _ in FakeSource(seconds: seconds) },
            pollInterval: .milliseconds(5))
    }

    @Test func aShortFileIsOneChunkAndFinishes() async {
        let transcriber = FakeTranscriber()
        let job = makeJob(seconds: 7, transcriber: transcriber)
        await job.run()
        #expect(job.phase == .finished)
        #expect(transcriber.calls == 1)
        #expect(job.text == "[00:00:01]\nchunk1.")
    }

    @Test func timesAreShiftedByWhereTheChunkStarts() async {
        // 70 s of steady tone: the chunker cuts at 20.05 s and 40.10 s, then the rest.
        let transcriber = FakeTranscriber()
        let job = makeJob(seconds: 70, transcriber: transcriber)
        await job.run()
        #expect(transcriber.calls == 3)
        let starts = job.paragraphs.map(\.start)
        #expect(starts.count == 3)
        for (start, expected) in zip(starts, [1, 21.05, 41.1]) {
            #expect(abs(start - expected) < 0.000_001)
        }
        #expect(job.phase == .finished)
    }

    @Test func theSpeakerPassLabelsParagraphs() async {
        let provider = FakeSpeakers()
        provider.result = .success([
            SpeakerTurn(speaker: "A", start: 0, end: 20.05), SpeakerTurn(speaker: "B", start: 20.05, end: 70),
        ])
        // 45 s is two chunks: 0–20.05 s and the rest, so one word at 1 s and one at 21.05 s.
        let job = makeJob(seconds: 45, speakers: .exactly(2), provider: provider)
        await job.run()
        #expect(provider.requested == .some(2))
        #expect(job.paragraphs.map(\.speaker) == [1, 2])
        #expect(job.text.hasPrefix("[00:00:01] Speaker 1\nchunk1."))
    }

    @Test func detectingSpeakersPassesNoCount() async {
        let provider = FakeSpeakers()
        let job = makeJob(seconds: 5, speakers: .detect, provider: provider)
        await job.run()
        #expect(provider.requested == .some(nil))
    }

    @Test func aFailedSpeakerPassFailsBeforeTranscribing() async {
        let transcriber = FakeTranscriber()
        let provider = FakeSpeakers()
        provider.result = .failure(FakeSpeakers.Boom())
        let job = makeJob(seconds: 30, speakers: .detect, transcriber: transcriber, provider: provider)
        await job.run()
        #expect(job.phase == .failed(FileTranscriptionJob.Message.speakersFailed))
        #expect(transcriber.calls == 0)
    }

    @Test func noModelLoadedFailsAtOnce() async {
        let transcriber = FakeTranscriber()
        transcriber.isModelLoaded = false
        let job = makeJob(seconds: 30, transcriber: transcriber)
        await job.run()
        #expect(job.phase == .failed(FileTranscriptionJob.Message.noModel))
        #expect(transcriber.calls == 0)
    }

    @Test func anUnreadableFileReportsItsOwnSentence() async {
        let job = makeJob(seconds: 0, open: { _ in throw AudioFileError.noAudioTrack })
        await job.run()
        #expect(job.phase == .failed("This file has no audio"))
    }

    @Test func aFileWithNoSpeechSaysSo() async {
        let transcriber = FakeTranscriber()
        transcriber.wordsPerChunk = [[]]
        let job = makeJob(seconds: 5, transcriber: transcriber)
        await job.run()
        #expect(job.phase == .failed(FileTranscriptionJob.Message.noSpeech))
    }

    @Test func anEmptyFileSaysNoSpeechWithoutCallingTheModel() async {
        let transcriber = FakeTranscriber()
        let job = makeJob(seconds: 0, transcriber: transcriber)
        await job.run()
        #expect(job.phase == .failed(FileTranscriptionJob.Message.noSpeech))
        #expect(transcriber.calls == 0)
    }

    @Test func aFailingChunkStopsTheJobAndKeepsTheText() async {
        let transcriber = FakeTranscriber()
        transcriber.failOnCall = 2
        let job = makeJob(seconds: 70, transcriber: transcriber)
        await job.run()
        #expect(job.phase == .failed("Transcription stopped: the model fell over"))
        #expect(job.paragraphs.count == 1)
    }

    @Test func aChangedModelStopsTheJobAndKeepsTheText() async {
        let transcriber = FakeTranscriber()
        transcriber.changeModelOnCall = 1
        let job = makeJob(seconds: 70, transcriber: transcriber)
        await job.run()
        #expect(job.phase == .failed(FileTranscriptionJob.Message.modelChanged))
        #expect(transcriber.calls == 1)
        #expect(job.paragraphs.count == 1)
    }

    @Test func cancellingStopsAfterTheCurrentChunkAndKeepsTheText() async {
        let transcriber = FakeTranscriber()
        let job = makeJob(seconds: 70, transcriber: transcriber)
        transcriber.onCall = { if transcriber.calls == 1 { job.cancel() } }
        await job.run()
        #expect(job.phase == .cancelled)
        #expect(transcriber.calls == 1)
        #expect(job.paragraphs.count == 1)
    }

    @Test func itWaitsWhileDictationIsActiveAndResumesAfter() async {
        let transcriber = FakeTranscriber()
        let dictation = FakeDictation()
        dictation.isDictating = true
        let job = makeJob(seconds: 7, transcriber: transcriber, dictation: dictation)
        let running = Task { await job.run() }
        try? await Task.sleep(for: .milliseconds(60))
        #expect(transcriber.calls == 0)
        #expect(job.phase == .pausedForDictation(0))
        dictation.isDictating = false
        await running.value
        #expect(transcriber.calls == 1)
        #expect(job.phase == .finished)
    }

    @Test func progressNeverGoesBackwardsAndIsRunningFollowsThePhase() async {
        let transcriber = FakeTranscriber()
        let job = makeJob(seconds: 70, transcriber: transcriber)
        var seen: [Double] = []
        transcriber.onCall = {
            if case .transcribing(let fraction) = job.phase { seen.append(fraction) }
            #expect(job.isRunning)
        }
        #expect(!job.isRunning)
        await job.run()
        #expect(seen == seen.sorted())
        #expect(seen.allSatisfy { $0 >= 0 && $0 <= 1 })
        #expect(!job.isRunning)
    }
}
```

- [ ] **Step 2: Run; it must fail to compile**

Run: `xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests/FileTranscriptionJobTests 2>&1 | grep -E "error:|\*\* TEST" | head`
Expected: `error: cannot find 'FileTranscriptionJob' in scope`

- [ ] **Step 3: Write `FileTranscriptionJob.swift`**

```swift
import Foundation
import Observation

/// Whether a dictation session is under way; file transcription waits while one is.
protocol DictationActivity: AnyObject {
    var isDictating: Bool { get }
}

/// Who spoke when in a file.
protocol SpeakerTurnProviding: AnyObject {
    func turns(for url: URL, speakerCount: Int?) async throws -> [SpeakerTurn]
}

/// What the user asked for about speakers.
nonisolated enum SpeakerRequest: Equatable, Sendable {
    case none
    case detect
    case exactly(Int)
}

/// One file's transcription, from the first sample to the last paragraph. It transcribes a
/// chunk at a time and, before each chunk, waits while dictation is active: dictation is
/// the app's first job and must never queue behind a long file.
@Observable
final class FileTranscriptionJob {
    enum Phase: Equatable {
        case idle
        case identifyingSpeakers
        /// The fraction of the file's duration transcribed so far.
        case transcribing(Double)
        case pausedForDictation(Double)
        case finished
        case cancelled
        case failed(String)
    }

    enum Message {
        static let noModel = "Choose a transcription model in Settings first"
        static let speakersFailed = "Couldn't identify speakers in this file"
        static let modelChanged = "The transcription model changed"
        static let noSpeech = "No speech was found in this file"
        static func stopped(_ reason: String) -> String { "Transcription stopped: \(reason)" }
    }

    private(set) var phase: Phase = .idle
    private(set) var paragraphs: [TranscriptParagraph] = []
    var text: String { TranscriptBuilder.text(paragraphs) }

    var isRunning: Bool {
        switch phase {
        case .identifyingSpeakers, .transcribing, .pausedForDictation: true
        case .idle, .finished, .cancelled, .failed: false
        }
    }

    let url: URL
    private let language: String?
    private let speakers: SpeakerRequest
    private let transcriber: any TimedTranscribing
    private let dictation: any DictationActivity
    private let speakerProvider: any SpeakerTurnProviding
    private let openSource: @Sendable (URL) async throws -> any FileAudioSource
    private let pollInterval: Duration
    private var cancelRequested = false
    private var task: Task<Void, Never>?

    init(
        url: URL, language: String?, speakers: SpeakerRequest,
        transcriber: any TimedTranscribing, dictation: any DictationActivity,
        speakerProvider: any SpeakerTurnProviding,
        openSource: @escaping @Sendable (URL) async throws -> any FileAudioSource = { try await AudioFileDecoder.open($0) },
        pollInterval: Duration = .milliseconds(200)
    ) {
        self.url = url
        self.language = language
        self.speakers = speakers
        self.transcriber = transcriber
        self.dictation = dictation
        self.speakerProvider = speakerProvider
        self.openSource = openSource
        self.pollInterval = pollInterval
    }

    func start() {
        guard task == nil else { return }
        task = Task { await run() }
    }

    /// Stops after the chunk in flight; the text so far stays.
    func cancel() {
        cancelRequested = true
    }

    func run() async {
        guard transcriber.isModelLoaded else {
            phase = .failed(Message.noModel)
            return
        }
        let generation = transcriber.modelGeneration

        let source: any FileAudioSource
        do {
            source = try await openSource(url)
        } catch let error as AudioFileError {
            phase = .failed(error.message)
            return
        } catch {
            phase = .failed(AudioFileError.notReadable.message)
            return
        }

        var turns: [SpeakerTurn] = []
        if speakers != .none {
            phase = .identifyingSpeakers
            do {
                let count: Int? = if case .exactly(let number) = speakers { number } else { nil }
                turns = try await speakerProvider.turns(for: url, speakerCount: count)
            } catch {
                phase = .failed(Message.speakersFailed)
                return
            }
            if cancelRequested {
                phase = .cancelled
                return
            }
        }

        let duration = source.duration
        var words: [TimedWord] = []
        var chunker = AudioChunker()
        var fraction = 0.0
        phase = .transcribing(0)

        /// Transcribes one chunk; false when the job has ended (its phase says why).
        func transcribe(_ chunk: AudioChunk) async -> Bool {
            while dictation.isDictating {
                if cancelRequested { break }
                phase = .pausedForDictation(fraction)
                try? await Task.sleep(for: pollInterval)
            }
            if cancelRequested {
                phase = .cancelled
                return false
            }
            guard transcriber.isModelLoaded, transcriber.modelGeneration == generation else {
                phase = .failed(Message.modelChanged)
                return false
            }
            phase = .transcribing(fraction)
            do {
                let chunkWords = try await transcriber.transcribeTimed(chunk.samples, language: language)
                words += chunkWords.map {
                    TimedWord(text: $0.text, start: $0.start + chunk.startSeconds, end: $0.end + chunk.startSeconds)
                }
            } catch {
                phase = .failed(Message.stopped(error.localizedDescription))
                return false
            }
            paragraphs = TranscriptBuilder.paragraphs(words: words, turns: turns)
            let end = chunk.startSeconds + Double(chunk.samples.count) / Double(AudioChunker.sampleRate)
            fraction = duration > 0 ? min(1, max(fraction, end / duration)) : fraction
            if transcriber.modelGeneration != generation {
                phase = .failed(Message.modelChanged)
                return false
            }
            if cancelRequested {
                phase = .cancelled
                return false
            }
            phase = .transcribing(fraction)
            return true
        }

        do {
            while let samples = try await source.next() {
                for chunk in chunker.append(samples) {
                    guard await transcribe(chunk) else { return }
                }
            }
        } catch let error as AudioFileError {
            phase = .failed(error.message)
            return
        } catch {
            phase = .failed(AudioFileError.notReadable.message)
            return
        }
        if let last = chunker.finish() {
            guard await transcribe(last) else { return }
        }
        phase = paragraphs.isEmpty ? .failed(Message.noSpeech) : .finished
    }
}
```

- [ ] **Step 4: Run; all fourteen tests pass**

Run the Step 2 command. Expected: `** TEST SUCCEEDED **`.

Notes if a test fails:
- `timesAreShiftedByWhereTheChunkStarts` expects cuts at 20.05 s and 40.10 s: on a steady tone every window ties, the chunker keeps the first (at 20.0 s) and cuts at its middle (20.05 s). If the chunker from Task 2 differs, fix the expectation only after confirming the chunker's own tests pass.
- `aChangedModelStopsTheJobAndKeepsTheText`: the fake changes the generation *during* the first call, so the first chunk's words are kept and the check after the call ends the job.

- [ ] **Step 5: Run the whole unit suite, then commit**

```bash
xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests 2>&1 | grep -E "error:|\*\* TEST" | tail -3
git add app/justscribe/Services/FileTranscription/FileTranscriptionJob.swift app/justscribeTests/FileTranscriptionJobTests.swift
git commit -m "Run a file through the speech model chunk by chunk, yielding to dictation"
```

---

### Task 6: Speaker diarization service

**Files:**
- Create: `app/justscribe/Services/FileTranscription/SpeakerDiarizationService.swift`
- Test: `app/justscribeTests/SpeakerDiarizationServiceTests.swift`

**Interfaces:**
- Consumes: `SpeakerTurn` (Task 1), `SpeakerTurnProviding` (Task 5).
- Produces: `SpeakerDiarizationService.shared` (`@Observable`, main actor, conforms to `SpeakerTurnProviding`): `private(set) var isReady: Bool`, `private(set) var downloadProgress: Double?`, `func prepare() async throws`; `nonisolated static func turns(fromSegments: [(speaker: String, start: Float, end: Float)]) -> [SpeakerTurn]`.

The model work itself cannot run in unit tests (it downloads 22 MB and runs Core ML); the mapping from the diarizer's segments to `SpeakerTurn` is the tested part, and the rest is exercised by hand in Task 8.

- [ ] **Step 1: Write the failing test `SpeakerDiarizationServiceTests.swift`**

```swift
import Testing
@testable import justscribe

struct SpeakerDiarizationServiceTests {

    @Test func segmentsBecomeTurnsInTimeOrder() {
        let turns = SpeakerDiarizationService.turns(fromSegments: [
            (speaker: "S2", start: 5.5, end: 9.0),
            (speaker: "S1", start: 0.25, end: 5.5),
        ])
        #expect(turns == [
            SpeakerTurn(speaker: "S1", start: 0.25, end: 5.5),
            SpeakerTurn(speaker: "S2", start: 5.5, end: 9.0),
        ])
    }

    @Test func emptyAndBackwardsSegmentsAreDropped() {
        let turns = SpeakerDiarizationService.turns(fromSegments: [
            (speaker: "S1", start: 2, end: 2),
            (speaker: "S1", start: 4, end: 3),
            (speaker: "S1", start: 5, end: 6),
        ])
        #expect(turns == [SpeakerTurn(speaker: "S1", start: 5, end: 6)])
    }
}
```

- [ ] **Step 2: Run; it must fail to compile**

Run: `xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests/SpeakerDiarizationServiceTests 2>&1 | grep -E "error:|\*\* TEST" | head`
Expected: `error: cannot find 'SpeakerDiarizationService' in scope`

- [ ] **Step 3: Write `SpeakerDiarizationService.swift`**

```swift
import FluidAudio
import Foundation
import Observation

/// Says who spoke when in a file, with FluidAudio's offline diarizer. Its models (about
/// 22 MB) are separate from the speech model and are downloaded the first time they are
/// needed, into the same place as the Parakeet models.
@Observable
final class SpeakerDiarizationService: SpeakerTurnProviding {
    static let shared = SpeakerDiarizationService()

    /// The models are downloaded and loaded.
    private(set) var isReady = false
    /// 0…1 while the models are being downloaded or compiled, nil otherwise.
    private(set) var downloadProgress: Double?

    private var models: OfflineDiarizerModels?

    private init() {}

    /// Downloads (once) and loads the diarizer's models.
    func prepare() async throws {
        if models != nil { return }
        downloadProgress = 0
        defer { downloadProgress = nil }
        let loaded = try await OfflineDiarizerModels.load { progress in
            Task { @MainActor in
                SpeakerDiarizationService.shared.downloadProgress = progress.fractionCompleted
            }
        }
        models = loaded
        isReady = true
    }

    func turns(for url: URL, speakerCount: Int?) async throws -> [SpeakerTurn] {
        try await prepare()
        guard let models else { return [] }
        var config = OfflineDiarizerConfig.default
        if let speakerCount {
            config = config.withSpeakers(exactly: speakerCount)
        }
        let box = ModelsBox(models: models)
        // The diarizer is heavy; keep it off the main actor.
        let segments = try await Task.detached(priority: .userInitiated) {
            let manager = OfflineDiarizerManager(config: config)
            manager.initialize(models: box.models)
            return try await manager.process(url).segments.map {
                (speaker: $0.speakerId, start: $0.startTimeSeconds, end: $0.endTimeSeconds)
            }
        }.value
        return Self.turns(fromSegments: segments)
    }

    /// The diarizer's segments as turns, in time order, without empty ones.
    nonisolated static func turns(fromSegments segments: [(speaker: String, start: Float, end: Float)]) -> [SpeakerTurn] {
        segments
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
            .map { SpeakerTurn(speaker: $0.speaker, start: Double($0.start), end: Double($0.end)) }
    }
}

/// Core ML models are not Sendable but are only read after loading.
private nonisolated struct ModelsBox: @unchecked Sendable {
    let models: OfflineDiarizerModels
}
```

API notes, verified against FluidAudio 0.14.5 in the package checkout (`Sources/FluidAudio/Diarizer/Offline/Core/`): `OfflineDiarizerModels.load(from:configuration:progressHandler:)`, `OfflineDiarizerConfig.default`, `withSpeakers(exactly:)`, `OfflineDiarizerManager(config:)`, `initialize(models:)`, `process(_ url: URL) -> DiarizationResult` whose `segments` are `TimedSpeakerSegment` with `speakerId`, `startTimeSeconds`, `endTimeSeconds`. If a name differs in the resolved version, read those files and adapt; the tested contract is `turns(fromSegments:)`.

- [ ] **Step 4: Run the tests and the whole suite; commit**

```bash
xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests 2>&1 | grep -E "error:|\*\* TEST" | tail -3
git add app/justscribe/Services/FileTranscription/SpeakerDiarizationService.swift app/justscribeTests/SpeakerDiarizationServiceTests.swift
git commit -m "Identify speakers in a file with FluidAudio's offline diarizer"
```

Expected: `** TEST SUCCEEDED **`.

---

### Task 7: The window, and the menu item

**Files:**
- Create: `app/justscribe/Views/FileTranscription/FileTranscriptionModel.swift`
- Create: `app/justscribe/Views/FileTranscription/FileTranscriptionView.swift`
- Create: `app/justscribe/Views/FileTranscription/FileTranscriptionWindowController.swift`
- Modify: `app/justscribe/AppDelegate.swift`
- Test: `app/justscribeTests/FileTranscriptionModelTests.swift`

**Interfaces:**
- Consumes: `FileTranscriptionJob`, `SpeakerRequest`, `DictationActivity` (Task 5); `SpeakerDiarizationService` (Task 6); `TranscriptionService` (Task 3).
- Produces: `FileTranscriptionModel` (`@Observable`): `var identifySpeakers: Bool`, `var speakerCountText: String`, `private(set) var job: FileTranscriptionJob?`, `private(set) var notice: String?`, `var speakerRequest: SpeakerRequest`, `func open(_ url: URL)`, `func reset()`, `static func speakerRequest(identify: Bool, countText: String) -> SpeakerRequest`, `static func saveName(for url: URL) -> String`; `FileTranscriptionWindowController.show()`.

- [ ] **Step 1: Write the failing tests `FileTranscriptionModelTests.swift`**

```swift
import Foundation
import Testing
@testable import justscribe

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
}
```

- [ ] **Step 2: Run; it must fail to compile**

Run: `xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests/FileTranscriptionModelTests 2>&1 | grep -E "error:|\*\* TEST" | head`
Expected: `error: cannot find 'FileTranscriptionModel' in scope`

- [ ] **Step 3: Write `FileTranscriptionModel.swift`**

```swift
import AppKit
import Foundation
import Observation

/// The state behind the Transcribe File window: the options, the current job, and the
/// actions on its result. Nothing here outlives the window.
@Observable
final class FileTranscriptionModel {
    static let identifySpeakersKey = "fileTranscription.identifySpeakers"

    /// Whether to label speakers. Remembered between launches; turning it on fetches the
    /// speaker models the first time.
    var identifySpeakers: Bool {
        didSet {
            guard identifySpeakers != oldValue else { return }
            UserDefaults.standard.set(identifySpeakers, forKey: Self.identifySpeakersKey)
            if identifySpeakers { prepareSpeakerModels() }
        }
    }
    /// The number of speakers as typed; empty means "work it out".
    var speakerCountText = ""
    private(set) var job: FileTranscriptionJob?
    /// A sentence to show under the options: a failed download, or a file that was refused.
    private(set) var notice: String?

    let diarization: SpeakerDiarizationService
    private let transcriber: any TimedTranscribing
    private let dictation: any DictationActivity

    init(
        transcriber: any TimedTranscribing, dictation: any DictationActivity,
        diarization: SpeakerDiarizationService = .shared
    ) {
        self.transcriber = transcriber
        self.dictation = dictation
        self.diarization = diarization
        identifySpeakers = UserDefaults.standard.bool(forKey: Self.identifySpeakersKey)
    }

    var hasModel: Bool { transcriber.isModelLoaded }
    var speakerRequest: SpeakerRequest { Self.speakerRequest(identify: identifySpeakers, countText: speakerCountText) }

    nonisolated static func speakerRequest(identify: Bool, countText: String) -> SpeakerRequest {
        guard identify else { return .none }
        if let count = Int(countText.trimmingCharacters(in: .whitespaces)), (1...10).contains(count) {
            return .exactly(count)
        }
        return .detect
    }

    nonisolated static func saveName(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent + ".txt"
    }

    /// Starts transcribing `url`, with speakers as the options say.
    func open(_ url: URL) {
        start(url, speakers: speakerRequest)
    }

    /// Runs the same file again without the speaker pass, after that pass failed.
    func retryWithoutSpeakers() {
        guard let url = job?.url else { return }
        start(url, speakers: .none)
    }

    private func start(_ url: URL, speakers: SpeakerRequest) {
        guard job?.isRunning != true else { return }
        notice = nil
        let language = UserDefaults.standard.string(forKey: AppSettings.selectedLanguageKey)
        let job = FileTranscriptionJob(
            url: url, language: language, speakers: speakers,
            transcriber: transcriber, dictation: dictation, speakerProvider: diarization)
        self.job = job
        job.start()
    }

    func cancel() {
        job?.cancel()
    }

    /// Back to the drop zone; the transcript is gone.
    func reset() {
        guard job?.isRunning != true else { return }
        job = nil
        notice = nil
    }

    func copy() {
        guard let text = job?.text, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func save() {
        guard let job, !job.text.isEmpty else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Self.saveName(for: job.url)
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try job.text.write(to: destination, atomically: true, encoding: .utf8)
        } catch {
            notice = "Couldn't save the transcript: \(error.localizedDescription)"
        }
    }

    private func prepareSpeakerModels() {
        guard !diarization.isReady else { return }
        notice = nil
        Task {
            do {
                try await diarization.prepare()
            } catch {
                notice = "Couldn't download the speaker model. Check your connection and try again"
                identifySpeakers = false
            }
        }
    }
}
```

- [ ] **Step 4: Run the model tests; they pass**

Run the Step 2 command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Write `FileTranscriptionView.swift`**

```swift
import SwiftUI
import UniformTypeIdentifiers

struct FileTranscriptionView: View {
    @Bindable var model: FileTranscriptionModel
    let openSettings: () -> Void

    @State private var isChoosingFile = false
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let job = model.job {
                jobView(job)
            } else {
                startView
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.audio, .movie]) { result in
            if case .success(let url) = result { model.open(url) }
        }
    }

    // MARK: - Before a file is chosen

    private var startView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 10) {
                Image(systemName: "waveform.badge.plus")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text("Drop an audio or video file here")
                    .font(.headline)
                Button("Choose File…") { isChoosingFile = true }
                    .buttonStyle(.pill)
                    .disabled(!model.hasModel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isDropTargeted ? Color.accentColor : Color(nsColor: .separatorColor),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            )
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                guard model.hasModel, let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in model.open(url) }
                }
                return true
            }

            if !model.hasModel {
                HStack {
                    Label(FileTranscriptionJob.Message.noModel, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Settings", action: openSettings).buttonStyle(.pill)
                }
                .font(.callout)
            }

            speakerOptions

            if let notice = model.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var speakerOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Identify speakers").font(.body)
                    Text("Labels who said what. Uses a small extra model, downloaded once.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $model.identifySpeakers)
                    .toggleStyle(.pill)
                    .labelsHidden()
            }
            if let progress = model.diarization.downloadProgress {
                ProgressView(value: progress) { Text("Downloading the speaker model…").font(.caption) }
            }
            if model.identifySpeakers {
                HStack {
                    Text("Speakers").font(.callout)
                    TextField("Detect", text: $model.speakerCountText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    Text("Leave empty to detect, or enter 1 to 10.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - While a file runs, and after

    @ViewBuilder
    private func jobView(_ job: FileTranscriptionJob) -> some View {
        Text(job.url.lastPathComponent)
            .font(.headline)
            .lineLimit(1)
            .truncationMode(.middle)

        status(job)

        ScrollViewReader { proxy in
            ScrollView {
                Text(job.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                Color.clear.frame(height: 1).id("end")
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
            .onChange(of: job.paragraphs.count) {
                if job.isRunning { proxy.scrollTo("end", anchor: .bottom) }
            }
        }

        if let notice = model.notice {
            Text(notice).font(.caption).foregroundStyle(.secondary)
        }

        HStack {
            if job.isRunning {
                Button("Cancel") { model.cancel() }.buttonStyle(.pill)
            } else {
                Button("Transcribe Another") { model.reset() }.buttonStyle(.pill)
                if job.phase == .failed(FileTranscriptionJob.Message.speakersFailed) {
                    Button("Transcribe Without Speakers") { model.retryWithoutSpeakers() }.buttonStyle(.pill)
                }
                if job.phase == .failed(FileTranscriptionJob.Message.noModel) {
                    Button("Open Settings", action: openSettings).buttonStyle(.pill)
                }
            }
            Spacer()
            Button("Copy") { model.copy() }
                .buttonStyle(.pill)
                .disabled(job.text.isEmpty)
            Button("Save…") { model.save() }
                .buttonStyle(.pill)
                .disabled(job.text.isEmpty)
        }
    }

    @ViewBuilder
    private func status(_ job: FileTranscriptionJob) -> some View {
        switch job.phase {
        case .idle:
            EmptyView()
        case .identifyingSpeakers:
            ProgressView { Text("Identifying speakers…").font(.caption) }
                .progressViewStyle(.linear)
        case .transcribing(let fraction):
            ProgressView(value: fraction) { Text("Transcribing… \(Int(fraction * 100))%").font(.caption) }
        case .pausedForDictation(let fraction):
            ProgressView(value: fraction) { Text("Paused while you dictate").font(.caption) }
        case .finished:
            Label("Done", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.secondary)
        case .cancelled:
            Label("Cancelled", systemImage: "xmark.circle").font(.caption).foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.secondary)
        }
    }
}
```

`.buttonStyle(.pill)` and `.toggleStyle(.pill)` are defined in `Views/Settings/Components/PillStyles.swift`.

- [ ] **Step 6: Write `FileTranscriptionWindowController.swift`**

```swift
import AppKit
import SwiftUI

/// The Transcribe File window. A plain AppKit window hosting the SwiftUI view: a menu-bar
/// app can open and focus it directly, and it can ask before closing on a running job.
final class FileTranscriptionWindowController: NSObject, NSWindowDelegate {
    private let model: FileTranscriptionModel
    private let openSettings: () -> Void
    private var window: NSWindow?

    init(model: FileTranscriptionModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            window.title = "Transcribe File"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: FileTranscriptionView(model: model, openSettings: openSettings))
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("FileTranscriptionWindow")
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.job?.isRunning == true else { return true }
        let alert = NSAlert()
        alert.messageText = "Stop transcribing?"
        alert.informativeText = "The transcript so far will be lost."
        alert.addButton(withTitle: "Stop")
        alert.addButton(withTitle: "Keep Transcribing")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        model.cancel()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        // Nothing is kept: closing the window discards the transcript.
        model.reset()
    }
}
```

`model.reset()` does nothing while a job is still running; after a confirmed "Stop" the job ends on its own after the chunk in flight, and the next `show()` starts from whatever state it reached. That is acceptable: the user chose to stop.

- [ ] **Step 7: Wire it into `AppDelegate.swift`**

Add a stored property next to `statusItem`:

```swift
    private lazy var fileTranscription = FileTranscriptionWindowController(
        model: FileTranscriptionModel(transcriber: TranscriptionService.shared, dictation: self),
        openSettings: { [weak self] in self?.openSettings() }
    )
```

In `setupStatusBar()`, after the "Start Transcription" item:

```swift
        menu.addItem(NSMenuItem(title: "Transcribe File…", action: #selector(transcribeFileFromMenu), keyEquivalent: ""))
```

Next to `openSettings()`:

```swift
    @objc private func transcribeFileFromMenu() {
        fileTranscription.show()
    }
```

At the end of the file:

```swift
extension AppDelegate: DictationActivity {
    /// A dictation session, from key down until the final text has been typed.
    var isDictating: Bool { sessionState != .idle }
}
```

`openSettings` is `@objc private`; calling it from the closure inside the class is fine. If the compiler complains about `self` in the lazy initializer, declare the property as `private var fileTranscription: FileTranscriptionWindowController?` and create it on first use inside `transcribeFileFromMenu()`.

- [ ] **Step 8: Build, run the whole unit suite, commit**

```bash
xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests 2>&1 | grep -E "error:|warning: .*FileTranscription|\*\* TEST" | tail -5
git add app/justscribe/Views/FileTranscription app/justscribe/AppDelegate.swift app/justscribeTests/FileTranscriptionModelTests.swift
git commit -m "Transcribe File window with speaker options, progress, copy and save"
```

Expected: `** TEST SUCCEEDED **`, no warnings from the new files.

---

### Task 8: Documentation, privacy page, and the maintainer's hand checks

**Files:**
- Modify: `CLAUDE.md`, `README.md`, `web/src/pages/privacy.md`

- [ ] **Step 1: `CLAUDE.md`** — after the "Transcription providers" section add:

```markdown
### File transcription

"Transcribe File…" in the status-item menu opens an AppKit window
(`Views/FileTranscription/`) over a second pipeline in `Services/FileTranscription/`:
`AudioFileDecoder` (AVFoundation → 16 kHz mono) → `AudioChunker` (20–30 s chunks cut at
quiet points) → `TranscriptionService.transcribeTimed` (words with times) →
`TranscriptBuilder` (paragraphs, with speakers from `SpeakerDiarizationService` when asked).
`FileTranscriptionJob` drives one file and waits between chunks while
`AppDelegate.isDictating`: dictation always goes first. Every use of the speech model goes
through `TranscriptionService`'s `InferenceGate`, one request at a time; a new inference
path that bypasses it will run the model concurrently with dictation. Nothing about a file
is persisted. `TimedWord.text` keeps the model's own leading space, and transcripts are
built by concatenation, so languages written without spaces stay intact — do not "join
with spaces".
```

- [ ] **Step 2: `README.md`** — in the Features list, after the grammar correction bullet, add:

```markdown
- Transcribe audio and video files, with timestamps and optional speaker labels
```

- [ ] **Step 3: `web/src/pages/privacy.md`** — in "When the App uses the network", extend the first bullet's first sentence to: "When you choose a transcription model, the optional Llama grammar model, or turn on speaker identification for file transcription, the App downloads the model from Hugging Face (huggingface.co)." In "How the App works" add a bullet: "Files you transcribe are read where they are. They are not copied or uploaded, and the transcript is discarded when you close the window unless you save it." Set `updated` to the date of the change.

- [ ] **Step 4: Verify and commit**

```bash
(cd web && npm run build >/dev/null && npm run check:dist | tail -1)
xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests 2>&1 | grep -E "\*\* TEST" | tail -1
git add CLAUDE.md README.md web/src/pages/privacy.md
git commit -m "docs: file transcription in the project guide, README and privacy policy"
```

Expected: `dist/ is consistent: …` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Hand checks (maintainer, running the branch from Xcode)**

These cannot be automated; do them before merging, because merging to `main` releases.

1. Menu bar → **Transcribe File…** opens the window; with a model loaded, drop a two-speaker recording of a few minutes. Text appears paragraph by paragraph with `[HH:MM:SS]` times; progress reaches 100% and "Done".
2. Turn on **Identify speakers**: the model downloads once with a progress bar; the transcript shows `Speaker 1` / `Speaker 2`. Enter `2` in Speakers and run again.
3. Repeat with a Whisper model selected in Settings.
4. A video file (`.mp4` or `.mov`) transcribes; a video with no audio track says "This file has no audio"; a text file renamed to `.mp3` says "JustScribe can't read this file".
5. During a long file, hold the dictation shortcut and speak into another app: the window shows "Paused while you dictate", dictation works, and the file resumes on release.
6. During a long file, switch the model in Settings: the job stops with "The transcription model changed" and keeps its text.
7. **Copy** and **Save…** produce exactly the text shown; closing the window mid-job asks "Stop transcribing?".
8. An hour-long file: watch memory in Activity Monitor; it should not grow with the length of the file.
9. A recording in a language without spaces between words (if one is to hand) has no spaces inserted.

After release (a `web:` change, once the version is published): update the "File transcription" rows in `web/src/pages/macwhisper-alternative.md` and `superwhisper-alternative.md`, the home page feature list and `llms.txt`, and bump those pages' `updated` dates.
