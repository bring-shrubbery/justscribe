# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

JustScribe is a native macOS menu-bar app for hold-to-record voice dictation that types transcribed
text into whatever app has focus. All transcription and grammar correction run on-device.
SwiftUI + AppKit, sandboxed, GPL-3.0.

## Commands

```bash
xcodebuild -scheme justscribe -configuration Debug build
```

```bash
xcodebuild -scheme justscribe -destination 'platform=macOS' test
```

Single test (Swift Testing):

```bash
xcodebuild -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests/justscribeTests/example
```

No lint step is configured.

## Architecture

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

### Settings persistence — dual-write, deliberately

`AppSettings` is a SwiftData `@Model` used by the Settings UI, but every field mirrors itself into
**UserDefaults** through `didSet` (plus `syncToUserDefaults()`, since `didSet` doesn't fire on
SwiftData load). AppDelegate and the services read UserDefaults only — they never touch SwiftData.
When adding a setting, add the `static let ...Key`, the `didSet` mirror, *and* the line in
`syncToUserDefaults()`, or it will silently not apply at runtime.

Shortcuts have their own model (`Models/ShortcutConfig.swift`): `HotkeyService` runs in two modes —
KeyboardShortcuts/Carbon Events for modifier+key combos, and a raw
`NSEvent.addGlobalMonitorForEvents(.flagsChanged)` monitor for modifier-only shortcuts.

## Conventions and gotchas

- The Xcode project uses file-system-synchronized groups: **new files under `justscribe/` are picked
  up automatically — never hand-edit `project.pbxproj`** to add them.
- Every source file carries the GPL-3.0 header (auto-inserted by
  `justscribe.xcodeproj/xcshareddata/IDETemplateMacros.plist`). Keep it on new files.
- Carbon `kVK_*` constants are `Int` in Swift, not `Int32` — don't cast when switching on them.
- `KeyboardShortcuts.Key(rawValue:)` is **not** optional; optional binding won't compile.
- SourceKit often reports "Cannot find type" for cross-file references in this project; verify with
  an actual `xcodebuild` before chasing it.
- App is sandboxed (`justscribe.entitlements`: audio-input, network client, user-selected files).
  Model files therefore land inside the container, not `~/.cache`.
- In-app tips use StoreKit; `Products.storekit` is the local testing configuration.
