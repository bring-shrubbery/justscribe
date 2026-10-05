# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

JustScribe is a native macOS menu-bar app for hold-to-record voice dictation that types transcribed
text into whatever app has focus. All transcription and grammar correction run on-device.
SwiftUI + AppKit, sandboxed, GPL-3.0.

## Commands

```bash
xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -configuration Debug build
```

```bash
xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test
```

Single test (Swift Testing):

```bash
xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests/justscribeTests/example
```

No lint step is configured.

## Architecture

The repository has three parts: `app/` (the Xcode project, sources, tests and release scripts), `web/` (the Astro site served at justscribe.quassum.com) and `docs/`. Source paths below are relative to `app/justscribe/`.

`justscribeApp.swift` is a thin `@main` shell: it owns the SwiftData container and the Settings
window scene. **The real app logic lives in `AppDelegate.swift`**, which orchestrates every
`@MainActor @Observable` singleton service.

### Recording lifecycle (AppDelegate)

`HotkeyService.onKeyDown/onKeyUp` drive a three-state machine (`idle → recording → finalizing`):

1. Key down → check model loaded + mic permission → `AudioCaptureService.startRecording()` (started
   *before* the overlay so no audio is lost) → `OverlayManager.showListening()` →
   `TranscriptionService.startStreamingTranscription(chunkInterval: 2.0)`.
2. During recording, streaming chunks arrive on `onTranscriptionUpdate`; only the *delta* is typed,
   tracked by `typedTextLength` via `ClipboardService.typeNewText(fullText:previouslyTypedLength:)`.
3. Key up → stop streaming → re-transcribe the full audio buffer for accuracy (30s timeout, falls
   back to the streamed text) → optional grammar correction, which *replaces* the already-typed text
   via `ClipboardService.replaceTypedText` → optional clipboard copy → reset to `idle`.

Text reaches the target app in one of two modes (`Models/TextInsertion.swift`,
`AppSettings.textInsertionModeKey`, read once at key down): **paste** (the default) does nothing
while speaking and sends one ⌘V with the finished text at the end; **type** uses synthetic `CGEvent`
keystrokes posted to `.cgSessionEventTap` as text arrives, then corrects in place. Accessibility
permission is required for both. In type mode, delta-typing plus `typedTextLength` is load-bearing —
breaking that bookkeeping causes duplicated or truncated output in the user's target app. Streaming
transcription runs in both modes: its text is the fallback when the final pass times out.

### Transcription providers

Two backends sit behind one unified model ID of the form `provider:variant`
(`Models/ModelProvider.swift`): **WhisperKit** (`whisperkit:*` Whisper CoreML variants) and
**FluidAudio** (`fluidaudio:*` Parakeet). `TranscriptionService` branches on
`UnifiedModelInfo.model(forID:).provider` for load and inference; `ModelDownloadService` handles
downloads and has to probe several on-disk locations (sandbox Documents, Caches, Application
Support) because the two SDKs cache models differently.

Grammar correction is a separate opt-in path with its own two-backend split, this time behind a
`GrammarBackend` protocol rather than an inline switch (`Services/Grammar/`).
`AppleFoundationGrammarBackend` uses the OS `FoundationModels` model — no download, no RAM budget,
but unavailable unless Apple Intelligence is enabled — and is the default selection.
`MLXGrammarBackend` runs Llama 3.1 8B 4-bit, downloaded on demand. `GrammarCorrectionService` is
just the router plus the `@Observable` state the settings UI binds to.

Because the Apple model needs no download, `isReadyToUse(_:)` — not "is it downloaded" — is the
question the UI and `AppDelegate` ask before loading. Apple's context window is ~4096 tokens, so
text over 4,000 characters is split by `GrammarTextChunker`, whose `chunks(t).joined() == t`
invariant is what keeps `ClipboardService.replaceTypedText` bookkeeping correct.

### File transcription

"Transcribe File…" in the status-item menu opens an AppKit window
(`Views/FileTranscription/`, state in `FileTranscriptionModel`) over a second pipeline in
`Services/FileTranscription/`: `AudioFileDecoder` (an actor; AVFoundation → 16 kHz mono) →
`AudioChunker` (20–30 s chunks cut at quiet points) → `TranscriptionService.transcribeTimed`
(words with times) → `TranscriptBuilder` (paragraphs). With speakers on,
`SpeakerDiarizationService` (FluidAudio's offline diarizer; its models are fetched when speakers
are first turned on, never inside a job) runs once over the whole file first; `TranscriptBuilder`
shows labels when its turns hold two or more speakers and numbers them by first appearance among
the words. `FileTranscriptionJob` drives one file, waits before the speaker pass and between
chunks while `AppDelegate.isDictating` (dictation always goes first), and rebuilds the paragraphs
off the main actor after each chunk, since the main actor also handles the hotkey.

Every use of the speech model goes through `TranscriptionService`'s `InferenceGate`
(`Services/InferenceGate.swift`), one request at a time in arrival order; a new inference path
that bypasses it runs the model concurrently with dictation. A caller cancelled while queued gets
`CancellationError` (that is how dictation's 30 s final-pass timeout fires behind a file chunk);
one cancelled after it was granted the gate runs and releases it. The speaker pass does not use
that gate and cannot be interrupted once started (the diarizer ignores cancellation), so passes
run one at a time on a gate of their own. The diarizer writes a raw copy of the file's audio
(`fluidaudio-streaming-*.raw`) to the container's `tmp` and deletes it only on success, so the
service sweeps those files at launch, before each pass and after a pass that threw — only between
passes. `transcribeTimed` pads a short buffer with trailing silence, Parakeet's to 1 s and
Whisper's to 2 s: Parakeet rejects audio under 0.3 s, and Whisper silently decodes nothing from
1 s or less; a file's last chunk can be that short.

Nothing about a file is persisted: closing the window calls `FileTranscriptionModel.discard()`,
and the abandoned job finishes its chunk in flight on its own. Transcripts are built by
concatenating the model's own pieces, never by joining with spaces, so languages written without
spaces stay intact. The assembler and the fallback paths put a space before a chunk's first word
(except punctuation), so an unspaced language can get a space at a chunk boundary on those paths.

### History

Off by default. `HistoryStore` (`Services/History/`) owns `Application Support/<bundle id>/History/`:
`index.json` (atomic writes, ISO 8601 dates) and `audio/<uuid>.m4a` (AAC mono 48 kbit/s from
`HistoryAudioWriter`, `@concurrent`). `AppDelegate.stopRecordingAndFinalize` asks
`HistoryPolicy.shouldKeep` with the two UserDefaults keys and hands the finished text and the
audio buffer to `HistoryStore.shared.add` in a Task; additions are chained so two in flight cannot
interleave. The audio folder is capped at 1 GB, oldest audio removed first, text kept. A damaged
index is renamed `index.json.broken`, never overwritten. The History window captures the frontmost
app on `show()` so "Paste" can activate it and paste through `ClipboardService.paste`. Tests use
temp directories only: never the real History folder or `UserDefaults.standard`.

### Dictation pipeline: commands, vocabulary, modes

`Services/Dictation/DictationPipeline` turns the raw final transcript into the inserted text:
`VoiceCommandProcessor` (new line / paragraph, scratch that / delete that, stop recording, send /
press enter; spoken punctuation when on) → `VocabularyMatcher` ("heard as" forms, then exact
spellings, then sound-alikes; exact and sound-alike matches need a non-dictionary word —
`DictionaryWords` wraps `NSSpellChecker` — a run never crosses clause punctuation, a possessive
"'s" is kept, and entries under three letters get no sound-alikes) → clean-up through
`GrammarCorrectionService.correctGrammar(_:instructions:language:)` with the mode's instructions
inside `GrammarPrompt.frame`. "Scratch that" fires anywhere; "delete that" and the layout and stop
commands need a clause boundary (`. ? ! , ; :`) on one side; "send" / "press enter" need a boundary before them
and must come last. "Stop recording" and "send" are commands only in press-to-toggle mode; in hold mode they are not in the command table and stay in the text as ordinary words. A line break
spoken at the end is kept, even through clean-up. `AppDelegate` builds a `DictationContext` at key
down (trigger, frontmost app → `ModeStore.mode(forApp:)`, vocabulary, switches) and keeps it for
the session; `stopRecordingAndFinalize` calls the pipeline where grammar correction used to run and
applies the result through the existing `replaceTypedText` bookkeeping. `RecordingTrigger` (`hold` /
`pressToToggle`) is read at key down; press mode ignores key up, stops on the next press, on a
spoken "stop recording" or "send" seen in the streaming text, on an overlay click, and after a 10-minute
safety stop. A modifier-only shortcut fires only after a short hold (0.15 s), in either mode.
Whisper gets the vocabulary as `promptTokens` (≤ 200); file transcripts get `VocabularyMatcher`
too, but no commands or clean-up. Vocabulary and modes live in `vocabulary.json` / `modes.json` in
the container through `JSONFile`; Default mode has a fixed UUID.

### Settings persistence — dual-write, deliberately

`AppSettings` is a SwiftData `@Model` used by the Settings UI, but every field mirrors itself into
**UserDefaults** through `didSet` (plus `syncToUserDefaults()`, since `didSet` doesn't fire on
SwiftData load). AppDelegate and the services read UserDefaults only — they never touch SwiftData.
When adding a setting, add the `static let ...Key`, the `didSet` mirror, *and* the line in
`syncToUserDefaults()`, or it will silently not apply at runtime.

Shortcuts have their own model (`Models/ShortcutConfig.swift`): `HotkeyService` runs in two modes —
KeyboardShortcuts/Carbon Events for modifier+key combos, and a raw
`NSEvent.addGlobalMonitorForEvents(.flagsChanged)` monitor for modifier-only shortcuts.

### Releases and updates

Every push to `main` that passes CI and changes code is released automatically
(`.github/workflows/release.yml`, `app/Scripts/release-*.sh`, `docs/release.md`): commit
subjects become the release notes users read, so prefix changes users never see with
`docs:`, `web:` or `ci:`, and keep unfinished work on a branch. Installed copies update
through Sparkle (`Services/UpdateService.swift`; feed and key in `Info.plist`). The app is
sandboxed, so Sparkle depends on `SUEnableInstallerLauncherService` and the two
mach-lookup entitlements in `justscribe.entitlements` — removing either breaks updates for
every installed copy.

### Menu bar app, and quitting

`LSUIElement` is set in `Info.plist`, so the app launches without a Dock icon; "Show in Dock"
(`showInDock`, default off) switches the activation policy to `.regular`. `AppSettings.getOrCreate`
moves a record from before that default to Dock-off once, under `menuBarOnlyMigrationKey`, and
`AppDelegate` ignores the stored value until that key is set. ⌘Q and "Quit JustScribe" go through
`applicationShouldTerminate`, which asks first ("Keep Running" closes the windows instead). Two
quits skip the question: one that carries a log-out/shutdown reason in its Apple event, and one
Sparkle sends to relaunch into an update, flagged by `UpdateService.isInstallingUpdate` from the
`SPUUpdaterDelegate` — without that flag an update would stall behind the alert. The Settings
window is reopened through `AppDelegate.openSettingsWindow`, set from the SwiftUI scene.

## Conventions and gotchas

- The Xcode project uses file-system-synchronized groups: **new files under `app/justscribe/` are picked
  up automatically — never hand-edit `project.pbxproj`** to add them.
- Every source file carries the GPL-3.0 header (auto-inserted by
  `app/justscribe.xcodeproj/xcshareddata/IDETemplateMacros.plist`). Keep it on new files.
- Carbon `kVK_*` constants are `Int` in Swift, not `Int32` — don't cast when switching on them.
- `KeyboardShortcuts.Key(rawValue:)` is **not** optional; optional binding won't compile.
- The recording indicator is `DynamicLanding` (github.com/bring-shrubbery/dynamic-landing, our own
  package): `OverlayManager` adapts the app's overlay states to one island per style — compact
  (waveform + timer) while listening in hold mode, expanded otherwise. Its geometry is pure and
  tested in the package; if the island ever looks wrong on a screen, the fix is a geometry test
  there, not a SwiftUI tweak here. The package is a normal SPM dependency in `project.pbxproj`.
- SourceKit often reports "Cannot find type" for cross-file references in this project; verify with
  an actual `xcodebuild` before chasing it.
- App is sandboxed (`justscribe.entitlements`: audio-input, network client, user-selected files).
  Model files therefore land inside the container, not `~/.cache`.
- The app target builds with default actor isolation `MainActor` and
  `SWIFT_APPROACHABLE_CONCURRENCY`, so a `nonisolated` async function runs on its caller's actor
  unless marked `@concurrent`. Heavy work must be `@concurrent`, in its own actor, or in
  `Task.detached`, or it blocks the main actor and with it the dictation hotkey.
- Microphones can deliver several channels, each in its own buffer, behind a non-contiguous
  `CMBlockBuffer`. `AudioCaptureService` reads them through an `AudioBufferList` and
  `PCMSampleConverter` averages them to one finite sample per frame; reading the block buffer
  as one run of bytes reads unrelated memory (NaN audio, recordings twice their length).
- Unit tests run inside the app and share its bundle ID: never write `UserDefaults.standard` from
  a test; inject a throwaway suite instead.
