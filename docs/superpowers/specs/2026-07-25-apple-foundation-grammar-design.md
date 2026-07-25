# Apple Foundation Models as a grammar correction backend

**Date:** 2026-07-25
**Status:** Approved

## Problem

Grammar correction currently requires downloading a 4.6 GB MLX model (Llama 3.1 8B 4-bit) that
needs ~5 GB of RAM to run. That is a steep price for a secondary feature, and it is the reason
grammar correction ships off by default.

macOS 26 exposes Apple's on-device foundation model through the `FoundationModels` framework. It
needs no download, no disk space, and no RAM budget from us. It should become the default grammar
correction backend, with the MLX model retained as an alternative.

## Scope

Add a second grammar correction backend and make it the default *selection*. Grammar correction
itself stays **off** by default, exactly as today. Existing installs that already selected the
Llama model keep it.

Out of scope: changing the transcription providers, changing the recording lifecycle, changing
when grammar correction runs.

## Decisions

| Question | Decision |
|---|---|
| What "default" means | `selectedGrammarModelID` defaults to the Apple model. `grammarCorrectionEnabled` stays `false`. Existing explicit Llama selections are untouched. |
| Apple Intelligence unavailable | Settings shows the specific reason plus a button to the relevant System Settings pane. At dictation time correction is skipped silently and the raw transcription stays typed — matching the existing error fallback. No overlay error, no auto-fallback to Llama. |
| Architecture | Protocol + two backends. `GrammarCorrectionService` becomes a router; its public surface is unchanged. |
| Text longer than the context window | Chunk on sentence boundaries, correct each chunk, rejoin. |

## SDK verification

Verified against `MacOSX26.5.sdk` (Xcode 26.6). All of the following are `@available(macOS 26.0)`,
below the project's 26.2 deployment target, so no availability guards are required:

- `SystemLanguageModel.default.availability -> Availability`, where
  `Availability = .available | .unavailable(UnavailableReason)` and
  `UnavailableReason = .deviceNotEligible | .appleIntelligenceNotEnabled | .modelNotReady`
- `LanguageModelSession(model:tools:instructions: String?)`
- `LanguageModelSession.prewarm(promptPrefix:)`
- `respond(to: String, options: GenerationOptions) async throws -> Response<String>`, `.content`
- `GenerationOptions(sampling:temperature:maximumResponseTokens:)`, `SamplingMode.greedy`
- `LanguageModelSession.GenerationError.guardrailViolation(_)` and `.exceededContextWindowSize(_)`

No entitlement changes: `FoundationModels` works inside the existing App Sandbox.

## Architecture

### Model catalog — `Models/GrammarCorrectionModel.swift`

`GrammarCorrectionModel` gains a backend discriminator. The download-related fields become
optional, since they are meaningless for the Apple model.

```swift
enum GrammarModelBackend { case apple, mlx }

struct GrammarCorrectionModel: Identifiable, Hashable {
    let id: String
    let displayName: String
    let provider: String
    let backend: GrammarModelBackend
    let hubID: String?
    let approximateSize: String?
    let approximateRAM: String?
    let approximateRAMInMB: Int?
}

static let appleFoundation = GrammarCorrectionModel(
    id: "apple-foundation",
    displayName: "Apple Intelligence",
    provider: "Built into macOS",
    backend: .apple,
    hubID: nil, approximateSize: nil, approximateRAM: nil, approximateRAMInMB: nil
)

static let allModels: [GrammarCorrectionModel] = [.appleFoundation, .llama3_1_8b_4bit]
static let defaultModelID = "apple-foundation"
```

Model IDs stay flat (no `provider:variant` prefix, unlike transcription). The existing persisted
value `"llama-3.1-8b-instruct-4bit"` therefore remains valid and no data migration is needed.

### Backend protocol — `Services/Grammar/GrammarBackend.swift`

```swift
enum GrammarBackendAvailability: Equatable {
    case available
    case requiresDownload                                // MLX, not on disk
    case unavailable(reason: String, settingsURL: URL?)
}

@MainActor
protocol GrammarBackend: AnyObject {
    var modelID: String { get }
    var availability: GrammarBackendAvailability { get }
    var isReady: Bool { get }
    func prepare(onProgress: @escaping @MainActor (Double) -> Void) async throws
    func correct(_ text: String, language: String?) async throws -> String
    func unload()
}
```

The shared timeout helper (currently inlined in `correctGrammar` as a `withThrowingTaskGroup`
race) moves here as a free function so both backends use one implementation.

### `Services/Grammar/MLXGrammarBackend.swift`

The current `GrammarCorrectionService` body, moved with no behavior change: on-disk probing of
`Library/Caches/models/<org>/<repo>/`, `loadModelContainer` with progress reporting, `ChatSession`
with the existing system prompt and `GenerateParameters(maxTokens: 2048, temperature: 0.1)`,
`session.clear()` before each request, model deletion, and the 30-second timeout.

`availability` returns `.available` when the model is on disk, `.requiresDownload` otherwise.

### `Services/Grammar/AppleFoundationGrammarBackend.swift`

`availability` maps `SystemLanguageModel.default.availability`:

| `UnavailableReason` | Message | Settings deep link |
|---|---|---|
| `.deviceNotEligible` | "Apple Intelligence isn't supported on this Mac." | none |
| `.appleIntelligenceNotEnabled` | "Turn on Apple Intelligence in System Settings." | Apple Intelligence & Siri pane |
| `.modelNotReady` | "macOS is still downloading the model. Try again shortly." | Apple Intelligence & Siri pane |

This mapping is a pure function of the reason and is unit-tested.

`prepare(onProgress:)` throws when unavailable; otherwise it constructs a `LanguageModelSession`
with the existing system prompt as `instructions:`, calls `prewarm()` to cut first-token latency,
and reports progress `1.0` immediately — there is nothing to download.

`correct(_:language:)`:

1. Build the prompt exactly as the MLX path does — bare text, or `"Language: <lang>. Text: <text>"`
   when a non-English language is selected.
2. Generate with `GenerationOptions(sampling: .greedy)`. Greedy sampling is deterministic, which
   is what we want for correction rather than generation.
3. Create a **fresh session per correction** so context never accumulates across dictations. This
   replaces the MLX path's `session.clear()`. Session construction is cheap once the model is
   resident.
4. Trim whitespace from the result, matching current behavior.
5. Apply a 20-second timeout per generation call.

`unload()` releases the session. The OS owns the model's memory; we do not.

**Error handling.** `guardrailViolation` and `exceededContextWindowSize` propagate as thrown
errors. The existing `catch` in `AppDelegate` (see `AppDelegate.swift:389`) already handles that by
keeping the raw transcription, which is the desired behavior.

### Chunking — `Services/Grammar/GrammarTextChunker.swift`

The Apple model's context window is ~4,096 tokens shared between prompt and response, so a long
dictation can overflow it.

```swift
enum GrammarTextChunker {
    static func chunks(_ text: String, maxLength: Int = 2000) -> [String]
}
```

Pure, no framework dependencies, fully unit-testable.

- Walks sentences with `enumerateSubstrings(in:options: .bySentences)` using the **enclosing**
  range, so inter-sentence whitespace is retained by whichever chunk it falls in.
- **Invariant: `chunks(t).joined() == t` for all `t`.** This is the primary test.
- Accumulates sentences into a chunk until adding the next would exceed `maxLength`.
- A single sentence longer than `maxLength` is split on word boundaries; a single word longer than
  `maxLength` is emitted as its own oversized chunk rather than being broken mid-word.

The Apple backend uses the single-shot path for text under 4,000 characters. Above that it chunks.
Each chunk is trimmed before being sent and its original leading/trailing whitespace is re-attached
to the corrected result, so rejoining reproduces the original spacing.

**Per-chunk failure is contained:** if one chunk throws (refusal, timeout), that chunk keeps its
original text and the remaining chunks are still corrected. Losing four good corrections because of
one refusal would be worse than a partially corrected result.

### Router — `Services/GrammarCorrectionService.swift`

Keeps its `@MainActor @Observable` singleton shape and its observable properties, which the
settings UI binds to directly: `isModelLoaded`, `isProcessing`, `isLoadingModel`, `loadProgress`,
`loadedModelID`, `activelyDownloadingModelID`, `downloadedModels`.

It owns one instance of each backend, resolves the backend for a given model ID, and forwards
`loadModel`, `correctGrammar`, `deleteModel`, and `unloadModel`. Progress reported by a backend
updates `loadProgress`; `activelyDownloadingModelID` is only ever set by the MLX backend.

One rename: **`isModelDownloaded(_:)` becomes `isReadyToUse(_:)`**, because "downloaded" is
false-by-construction for a model that is part of the OS. It returns `availability == .available`
for the model's backend. Three call sites update (`AppDelegate`, the settings section, the row
view).

`deleteModel(modelID:)` throws for the Apple model; the UI never offers it, so this is a guard
rather than a reachable path.

### Settings — `Models/AppSettings.swift`

- `selectedGrammarModelID` default changes from `""` to `GrammarCorrectionModel.defaultModelID`.
- `getOrCreate(in:)` normalizes a stored empty string to the default before calling
  `syncToUserDefaults()`. An install that never picked a model lands on Apple; an install already
  on Llama is untouched.
- `grammarCorrectionEnabled` default stays `false`.
- No new keys, so no additions to `syncToUserDefaults()`.

### Settings UI — `Views/Settings/Sections/GrammarCorrectionSettingsSection.swift`

The section still iterates `GrammarCorrectionModel.allModels` and switches on `backend` to pick a
row view.

`AvailableGrammarModelRow` is renamed `MLXGrammarModelRow` and is otherwise unchanged.

`AppleGrammarModelRow` is new:

- Icon `apple.intelligence` (falling back to `sparkles` if the symbol is unavailable at runtime),
  title "Apple Intelligence", subtitle "Built into macOS · No download".
- **Available, not selected** → a **Use** button that sets `selectedGrammarModelID` and calls
  `loadModel`.
- **Available, selected and loaded** → the same green "Loaded" label the MLX row uses.
- **Unavailable** → the reason text, plus an **Open Settings** button when a deep link exists.
- No download progress, no size/RAM line, no delete menu.

### Recording flow — `AppDelegate.swift`

**Unchanged.** The grammar correction block at `AppDelegate.swift:374` already gates on
`isModelLoaded` and catches all errors. The only edit in this file is the
`isModelDownloaded` → `isReadyToUse` rename in `loadGrammarModelIfEnabled()`.

## Testing

Unit tests (Swift Testing, `justscribeTests/`):

- `GrammarTextChunker`
  - `chunks(t).joined() == t` across a corpus: empty, whitespace-only, single sentence, many
    sentences, text with newlines, text with no sentence terminators.
  - Every chunk is `<= maxLength`, except where a single word exceeds it.
  - A sentence longer than `maxLength` is split on word boundaries.
  - Text shorter than `maxLength` yields exactly one chunk.
- Availability-reason mapping: each `UnavailableReason` produces the expected message, and only the
  two actionable reasons carry a settings URL.

Not unit-testable, verified by building and running on this Mac:

- Apple backend actually corrects text.
- The unavailable state renders correctly (can be forced by turning Apple Intelligence off).
- The System Settings deep link opens the right pane under App Sandbox. If it does not, fall back
  to opening System Settings generally.

## Conventions

- New files go under `justscribe/Services/Grammar/`; the Xcode project uses file-system-synchronized
  groups, so they are picked up without touching `project.pbxproj`.
- Every new file needs the GPL-3.0 header. The `IDETemplateMacros.plist` only fires for files
  created inside Xcode, so it must be added by hand here.
- `CLAUDE.md` gets a short paragraph describing the grammar backend split, mirroring how it
  documents the transcription providers.

## Files touched

| File | Change |
|---|---|
| `Models/GrammarCorrectionModel.swift` | Add `backend`, Apple entry, `defaultModelID`; optional download fields |
| `Services/Grammar/GrammarBackend.swift` | New — protocol, availability enum, timeout helper |
| `Services/Grammar/AppleFoundationGrammarBackend.swift` | New |
| `Services/Grammar/MLXGrammarBackend.swift` | New — extracted from the current service |
| `Services/Grammar/GrammarTextChunker.swift` | New |
| `Services/GrammarCorrectionService.swift` | Becomes a router; `isModelDownloaded` → `isReadyToUse` |
| `Models/AppSettings.swift` | Default model ID; empty-string normalization |
| `Views/Settings/Sections/GrammarCorrectionSettingsSection.swift` | Backend switch; new Apple row |
| `AppDelegate.swift` | Rename at one call site |
| `justscribeTests/` | Chunker and availability-mapping tests |
| `CLAUDE.md` | Document the backend split |
