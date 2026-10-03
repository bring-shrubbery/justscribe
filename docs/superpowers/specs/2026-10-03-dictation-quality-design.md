# Vocabulary, toggle recording, voice commands and modes — design

One release that makes dictation fit the person using it: the words it must
spell right, a shortcut that can be pressed instead of held, spoken commands
for layout and corrections, and clean-up instructions that follow the app in
front. All four meet in one place: a pure text pipeline that turns the raw
final transcript into the text that is inserted.

```
raw transcript ──► voice commands ──► vocabulary ──► clean-up (mode's instructions) ──► inserted text
                        │                                                           + actions (stop, Return)
```

## Decisions

| Question | Decision |
|---|---|
| Vocabulary entries | Both kinds in one list: the correct text, with optional "also heard as" forms. Entries with forms match them exactly; entries without are matched by sound and spelling. |
| Toggle recording | A setting, one behaviour at a time: **Hold to record** (default, as today) or **Press to start, press again to stop**. |
| Voice commands | Layout ("new line", "new paragraph") and editing ("scratch that", "delete that") on by default; "stop recording" / "send" in toggle mode; spoken punctuation behind an off-by-default switch. English phrases. |
| Modes | A name, clean-up instructions, a clean-up on/off switch and the apps it applies to. Picked automatically from the app in front at key-down; a built-in **Default** mode covers the rest. |
| Where it lives | `DictationPipeline`, a pure, tested stage called from `AppDelegate` where grammar correction runs today. Insertion bookkeeping (type and paste modes) is untouched. |
| Storage | `vocabulary.json` and `modes.json` in `Application Support/<bundle id>/`, atomic writes, like History. Settings switches through `AppSettings`' dual-write. No SwiftData. |

## Behaviour

### Vocabulary

- Settings → **Vocabulary**: a list of entries; **+** opens a row with *Text*
  (required) and *Also heard as* (optional, comma-separated); rows edit inline
  and delete; **Import from Clipboard** adds one entry per non-empty line
  (`text` alone, or `text = form, form`), skipping duplicates.
- An entry's `text` is inserted exactly as typed: "SwiftUI" fixes "swift UI",
  "Swift ui" and "swift-ui".
- Matching (all case-insensitive, whole words, tolerant of the punctuation and
  spacing the model adds between words):
  1. **Forms first:** each `heardAs` form is matched as a phrase and replaced.
  2. **Sound-alikes** for entries with no forms (and for entries with forms,
     as a fallback): a transcript word is a candidate when it is **not** a
     dictionary word (`NSSpellChecker` with the dictation language, falling
     back to English); it is replaced when its normalised spelling (lower
     case, no diacritics) is within edit distance 1 (≤ 5 letters) or 2 of the
     entry's, **or** its phonetic key (Metaphone rules, implemented in the
     app) equals the entry's.
     Multi-word entries are matched against runs of the same word count.
  3. A replaced word keeps the punctuation attached to it and the spacing
     around it.
- Dictionary words are never replaced by the sound-alike path: "mark" stays
  "mark" even with "Marc" in the vocabulary; add "mark" as a form to force it.
- **Whisper bias:** entries' `text`, most recently added first, joined with
  spaces and encoded with WhisperKit's tokenizer, capped at 200 tokens, is set
  as `DecodingOptions.promptTokens` for the final pass and the streaming
  passes. Parakeet has no prompt; it relies on the matcher.
- The matcher also runs on file transcripts: each chunk's words go through it
  before the paragraphs are rebuilt (a matched run becomes one word spanning
  the run's time). Nothing else about file transcription changes.

### Toggle recording

- Settings → Shortcut gets **Recording** under the recorder: *Hold to record*
  / *Press to start, press again to stop*, with the note "In press mode, say
  'stop recording' or press the shortcut again to finish. A recording stops
  by itself after 10 minutes."
- Hold mode is exactly today's behaviour.
- Press mode: key down while idle starts the session (capture, overlay,
  streaming, as today); key up is ignored; key down while recording stops and
  finalises; key down while finalising is ignored. The mode is read at key
  down and kept for the session.
- The overlay in press mode says **Recording — press the shortcut to stop**
  (plus the mode name when it is not Default: "Recording · Email"); clicking
  the overlay stops too.
- **Safety stop:** 10 minutes after a press-mode recording started, the
  session stops and finalises as if the shortcut had been pressed; the
  overlay's completed state says "Stopped after 10 minutes".
- The menu-bar item keeps toggling in both modes.

### Voice commands

- Settings → Behavior: **Voice Commands** (on by default) with the phrases as
  help text, and **Spoken Punctuation** (off by default).
- Phrases and effects (English):

  | Spoken | Effect |
  |---|---|
  | new line | line break |
  | new paragraph | blank line |
  | scratch that, delete that | removes the text from the nearest preceding *break* (end of the last sentence `. ? !`, or the last command's position, or the start) up to the command; the sentence end the model placed right before the command is the pause before it, not a break; said again with nothing new since, it removes the previous sentence |
  | stop recording, stop dictation | ends the session (press mode only; in hold mode the words are removed) |
  | send, press enter (at the very end of the text, and after a sentence end — "I'll send" is left alone) | ends the session, inserts the text, then posts a Return keystroke (press mode only; in hold mode the words are removed) |
  | *(spoken punctuation on)* period, full stop, comma, question mark, exclamation mark, exclamation point, colon, semicolon, open quote, close quote, dash | the character, glued to the previous word; quotes glue to the following/preceding word |

- "scratch that" is recognised anywhere: a correction is spoken mid-flow
  ("wrong words scratch that right words"), so no boundary is required (the
  cost: "I'd scratch that idea" also fires). "delete that" is common in
  ordinary speech ("can you delete that email"), so it follows the stand-alone
  rule like every other command: the token run is
  preceded by the start of the text or a sentence end, **or** followed by the
  end of the text or a sentence end (the model's own punctuation around the
  words counts, e.g. "…done. New line. Next" and "…done, new line, next" both
  fire; "a new line in the budget" does not). Case-insensitive.
- Removed commands leave no double spaces; a line break absorbs the spaces
  before it and a capital letter is not forced after it. A line break spoken
  at the very end is kept (the cursor lands on the new line); trailing spaces
  are not. A sentence end followed by a closing quote or bracket still counts
  as a sentence end for "scratch that".
- "stop recording" and "send" also act **live**: on each streaming update in
  press mode, if the streamed text ends with one of them, the session stops
  as if the shortcut had been pressed (so roughly two seconds after saying
  it, at the 2 s streaming interval). Hold mode never acts live.
- Commands run before vocabulary, so a vocabulary form can neither hide nor
  create a command, and before clean-up, so the model never sees the words.

### Modes

- Settings → **Clean-up** (renamed from Grammar Correction): the on/off
  switch (same key as today), the backend picker (Apple Intelligence / Llama,
  as today), then **Modes**: a list with the built-in **Default** first.
- A mode has *Name*, *Instructions* (multi-line), **Clean up text** (on by
  default; off means the raw transcript, after commands and vocabulary, goes
  to that mode's apps) and *Apps*: chips with the app icon and name; **+**
  lists the running apps and offers *Other…* (an open panel on
  `/Applications`). An app belongs to one mode; adding it elsewhere moves it.
  Default has no app list and cannot be deleted; its instructions can be
  edited and reset.
- Default's initial instructions are today's prompt: "Fix grammar, spelling
  and punctuation. Preserve the meaning and tone."
- Selection: at key down, `NSWorkspace.shared.frontmostApplication?.bundleIdentifier`
  is recorded for the session; the mode listing it wins, else Default. The
  overlay shows the mode's name when it is not Default.
- Clean-up runs when the global switch is on, the mode's switch is on, and
  the selected backend is loaded; a mode never triggers a download.
- Both backends wrap the mode's instructions in a fixed frame that keeps the
  output contract: the instructions, then "Apply this to the text that
  follows. Output only the resulting text: no explanations, no quotes, no
  preamble." Both backends already start a fresh session per request (so
  context never accumulates across dictations); the mode's framed
  instructions become that session's instructions, and the Apple backend
  prewarms a session with Default's. `GrammarTextChunker` is unchanged.

## Components

All under `app/justscribe/`. Pure types are `nonisolated` and tested.

### `Services/Dictation/DictationPipeline.swift`

```swift
nonisolated struct DictationContext: Sendable {
    var voiceCommands: Bool
    var spokenPunctuation: Bool
    var pressToToggle: Bool          // commands that end a session act only when true
    var vocabulary: [VocabularyEntry]
    var mode: DictationMode
    var cleanUpEnabled: Bool          // the global switch
    var language: String?
}
nonisolated enum DictationAction: Equatable, Sendable { case stopRecording, pressReturn }
nonisolated struct DictationResult: Equatable, Sendable { var text: String; var actions: [DictationAction] }

/// Pure except for clean-up, which is injected so tests pass a fake.
@MainActor final class DictationPipeline {
    init(cleanUp: @escaping (String, String, String?) async throws -> String)   // (text, instructions, language)
    func process(_ raw: String, context: DictationContext) async -> DictationResult
    /// The command that ends a session, if the streamed text ends with one.
    nonisolated static func terminatingCommand(in streamed: String, context: DictationContext) -> DictationAction?
}
```

`process`: `VoiceCommandProcessor.apply` → `VocabularyMatcher.apply` → clean-up
when `cleanUpEnabled && mode.cleanUp && !text.isEmpty`; a clean-up error or
empty result keeps the text from the previous stage (as today). Actions come
only from the command stage.

### `Services/Dictation/VoiceCommandProcessor.swift`

`nonisolated enum VoiceCommandProcessor` with
`static func apply(_ text: String, commandsOn: Bool, punctuationOn: Bool, sessionCommandsOn: Bool) -> (text: String, actions: [DictationAction])`
and the phrase tables. Tokenises on whitespace, keeps each token's trailing
punctuation, finds stand-alone command runs, applies them left to right
("scratch that" operates on the text built so far), then rejoins.

### `Services/Dictation/VocabularyMatcher.swift`

`nonisolated enum VocabularyMatcher` with
`static func apply(_ text: String, entries: [VocabularyEntry], isDictionaryWord: (String) -> Bool) -> String`,
`static func normalized(_ word: String) -> String`,
`static func editDistance(_ a: String, _ b: String) -> Int` and
`static func phoneticKey(_ word: String) -> String` (Metaphone rules,
implemented here — under 100 lines, no dependency). The dictionary
check is injected: production passes `NSSpellChecker.shared` with the
dictation language; tests pass a set.

### `Services/Dictation/VocabularyPrompt.swift`

`nonisolated enum VocabularyPrompt { static func text(_ entries: [VocabularyEntry]) -> String }`
— most recent first, joined with spaces. `TranscriptionService` encodes it
with the loaded WhisperKit tokenizer, truncates to 200 tokens, and sets
`promptTokens` on the Whisper decoding options for streaming and final
passes (`whisperKit.tokenizer?.encode(text:)`). Parakeet: unused.

### `Models/VocabularyEntry.swift`, `Models/DictationMode.swift`

```swift
nonisolated struct VocabularyEntry: Codable, Equatable, Identifiable, Sendable {
    var id: UUID; var text: String; var heardAs: [String]; var createdAt: Date
}
nonisolated struct DictationMode: Codable, Equatable, Identifiable, Sendable {
    var id: UUID; var name: String; var instructions: String; var cleanUp: Bool; var appBundleIDs: [String]
    static let defaultID: UUID   // a fixed UUID so Default survives reinstalls
    static let defaultInstructions: String
}
```

### `Services/Dictation/VocabularyStore.swift`, `ModeStore.swift`

`@Observable` main-actor classes, `static let shared`, `init(fileURL:)`,
`load()`, `entries`/`modes`, `add/update/delete`, `importLines(_:) -> Int`
(vocabulary), `mode(forApp:) -> DictationMode` and `assign(app:to:)`
(modes). JSON with ISO 8601 dates, atomic writes, a damaged file renamed
`.broken` and started afresh. `ModeStore.load()` inserts Default when it is
missing and keeps it first.

### `Services/Grammar/*` (changed)

`GrammarBackend.correct(_ text: String, instructions: String, language: String?)`.
`GrammarCorrectionService.correctGrammar(_:instructions:language:)`.
`AppleFoundationGrammarBackend`: `LanguageModelSession(instructions: framed)`
per request, Default's prewarmed. `MLXGrammarBackend`: a `ChatSession` with
the framed instructions per request over the loaded container.

### `AppDelegate.swift` (changed)

- Key down: reads `recordingTrigger`; records `frontmostApplication` bundle
  ID and the mode; in press mode while recording, calls the stop path; starts
  a 10-minute safety task in press mode (cancelled on stop).
- Streaming update: in press mode, `DictationPipeline.terminatingCommand`
  on the streamed text → stop.
- Finalise: where grammar correction runs today, `pipeline.process(raw, context)`;
  the result's `text` replaces `finalTranscription` (type mode still calls
  `replaceTypedText(characterCount:withText:)` when the text changed); after
  the paste/type, `.pressReturn` posts a Return key event through
  `ClipboardService` (new `pressReturn()` using the same CGEvent path as
  typing).
- Overlay texts for press mode and the mode name.

### `Models/AppSettings.swift` (changed)

`recordingTriggerKey = "recordingTrigger"` (String: `hold` | `toggle`,
default `hold`), `voiceCommandsEnabledKey = "voiceCommandsEnabled"` (Bool,
default true), `spokenPunctuationEnabledKey = "spokenPunctuationEnabled"`
(Bool, default false). `grammarCorrectionEnabledKey` keeps its name and
meaning (the global clean-up switch).

### Views

- `Views/Settings/Sections/VocabularySettingsSection.swift` (list, add row,
  import).
- `Views/Settings/Sections/GrammarCorrectionSettingsSection.swift` becomes
  `CleanUpSettingsSection.swift`: switch, backend, Modes list;
  `Views/Settings/Components/ModeEditor.swift` for the mode sheet with the
  app picker.
- `ShortcutSettingsSection`: the Recording picker. `BehaviorSettingsSection`:
  the two switches.
- `OverlayManager`: `showListening(hint: String?)` for "press the shortcut
  to stop" and the mode name; click-to-stop in press mode via a callback.
- Settings order: Model, Microphone, Shortcut, Indicator, Clean-up,
  Vocabulary, Appearance, Behavior, History, Updates, Support, Links.

### File transcription (changed)

`FileTranscriptionJob` takes `vocabulary: [VocabularyEntry]` (read once when
the job starts) and applies `VocabularyMatcher.apply(words:)` to each chunk's
words before rebuilding the paragraphs; absorbed words merge their time into
the kept one.

## Error handling

| Situation | Behaviour |
|---|---|
| Clean-up fails or returns empty | The text from the previous stage is used (as today); logged. |
| Vocabulary or modes file damaged | Renamed `.broken`, empty list (modes: Default recreated); Settings shows "A damaged vocabulary/modes file was set aside." |
| App in front has no bundle ID (none, or a non-app process) | Default mode. |
| Safety stop fires while finalising | Ignored (the session is already ending). |
| "send" with nothing to insert | No Return is pressed. |
| Whisper tokenizer unavailable | No prompt bias; the matcher still runs. |
| Mode's instructions blank | Treated as Default's instructions. |

## Privacy

`web/src/pages/privacy.md` "What is stored on your Mac" gains "your vocabulary
and dictation modes"; nothing leaves the Mac. Instructions go to the on-device
model only.

## Testing

- `VoiceCommandProcessor`: each phrase; stand-alone rule (fires after a
  sentence end, before the end, not in the middle of a clause); "scratch
  that" to the previous sentence, to the previous command, to the start;
  twice in a row; spoken punctuation on/off; session commands on/off; no
  double spaces; actions returned; terminating command at the end of streamed
  text only.
- `VocabularyMatcher`: form matching across spacing, hyphen and case;
  sound-alike on non-dictionary words; dictionary words untouched; edit
  distance bounds; metaphone known pairs ("Antony"→"Antoni", "quasum"→
  "Quassum", "swift ui"→"SwiftUI" via form); punctuation preserved;
  multi-word entries; idempotence (applying twice changes nothing).
- `VocabularyPrompt` ordering and cap (token truncation tested in
  `TranscriptionService` with a fake tokenizer closure).
- Stores on temp files: round trip, import parsing, Default insertion,
  `mode(forApp:)`, `assign` moving an app, damaged file set aside.
- `DictationPipeline` with a fake clean-up: order of stages; clean-up
  skipped when the switch or mode says so; failure keeps text; actions pass
  through.
- Backends: the frame contains the instructions (prompt-building helper
  tested as a pure function).
- By hand: hold and press modes with the shortcut and the menu; safety stop
  (lowered constant); "stop recording" live; "send" posts Return in a chat
  app; vocabulary with names in Parakeet and Whisper; a mode bound to Mail
  and a raw mode bound to Terminal; Apple and Llama backends.

## Out of scope

Non-English command phrases, a manual mode picker in the menu, per-mode
backends or models, importing vocabulary from files, syncing, and voice
commands in file transcription.
