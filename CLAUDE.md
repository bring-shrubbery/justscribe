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

Text insertion uses synthetic `CGEvent` Unicode keystrokes posted to `.cgSessionEventTap`, which is
why Accessibility permission is required. Delta-typing plus `typedTextLength` is load-bearing —
breaking that bookkeeping causes duplicated or truncated output in the user's target app.

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
`SpeakerDiarizationService` (FluidAudio's offline diarizer, models fetched on first use) runs
once over the whole file first; `TranscriptBuilder` shows labels when its turns hold two or more
speakers and numbers them by first appearance among the words. `FileTranscriptionJob` drives one
file, waits between chunks while `AppDelegate.isDictating` (dictation always goes first), and
rebuilds the paragraphs off the main actor after each chunk, since the main actor also handles
the hotkey. Every use of the speech model goes through `TranscriptionService`'s `InferenceGate`,
one request at a time; a new inference path that bypasses it runs the model concurrently with
dictation. The speaker pass does not use the gate and cannot be interrupted once started (the
diarizer ignores cancellation). `transcribeTimed` pads buffers to one second because Parakeet
rejects audio under 0.3 s and a file's last chunk can be shorter.

Nothing about a file is persisted: closing the window calls `FileTranscriptionModel.discard()`,
and the abandoned job finishes its chunk in flight on its own. `TimedWord.text` keeps the model's
own leading space and transcripts are built by concatenation, so languages written without
spaces stay intact — do not "join with spaces".

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

## Conventions and gotchas

- The Xcode project uses file-system-synchronized groups: **new files under `app/justscribe/` are picked
  up automatically — never hand-edit `project.pbxproj`** to add them.
- Every source file carries the GPL-3.0 header (auto-inserted by
  `app/justscribe.xcodeproj/xcshareddata/IDETemplateMacros.plist`). Keep it on new files.
- Carbon `kVK_*` constants are `Int` in Swift, not `Int32` — don't cast when switching on them.
- `KeyboardShortcuts.Key(rawValue:)` is **not** optional; optional binding won't compile.
- SourceKit often reports "Cannot find type" for cross-file references in this project; verify with
  an actual `xcodebuild` before chasing it.
- App is sandboxed (`justscribe.entitlements`: audio-input, network client, user-selected files).
  Model files therefore land inside the container, not `~/.cache`.
- The app target builds with default actor isolation `MainActor` and
  `SWIFT_APPROACHABLE_CONCURRENCY`, so a `nonisolated` async function runs on its caller's actor
  unless marked `@concurrent`. Heavy work must be `@concurrent`, in its own actor, or in
  `Task.detached`, or it blocks the main actor and with it the dictation hotkey.
- Unit tests run inside the app and share its bundle ID: never write `UserDefaults.standard` from
  a test; inject a throwaway suite instead.
