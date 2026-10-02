# File transcription with timestamps and speakers — design

JustScribe gains a second job beside dictation: turn an audio or video file
into a transcript with times and, optionally, speaker labels. Everything runs
on the Mac, with the speech model already loaded for dictation and FluidAudio's
offline diarizer.

```
[00:00:04] Speaker 1
So the first thing we looked at was the onboarding flow,
and where people dropped off.

[00:00:19] Speaker 2
Right, and that was mostly at the permissions step?
```

## Decisions

| Question | Decision |
|---|---|
| Output | Timestamped paragraphs, with speaker labels when requested |
| Where it lives | Its own window, opened from "Transcribe File…" in the status-item menu |
| While a file runs | Dictation takes priority: the file is processed in chunks and waits between them |
| How many files | One at a time |
| What is kept | Nothing: the transcript lives in the window until it is closed or replaced |
| Delivery | One release, built on a branch; timing lands before speakers so each step is testable |

## Behaviour

- The window starts as a drop zone with a **Choose File…** button, an
  **Identify speakers** switch (off by default; its state is remembered in
  UserDefaults) and, when the switch is on, a **Speakers** field (empty =
  detect; otherwise 1…10).
- A file is anything AVFoundation can decode to audio: m4a, mp3, wav, aiff,
  caf, flac, and the first audio track of mp4/mov/m4v.
- The job uses the model and language dictation is set to
  (`AppSettings.selectedModelIDKey`, `selectedLanguageKey`). With no model
  loaded the window says "Choose a transcription model in Settings first" and
  offers a button that opens Settings.
- Phases, each with progress: **Identifying speakers** (only when the switch is
  on), then **Transcribing** (fraction of the file's duration processed). Text
  appears paragraph by paragraph as chunks finish.
- **Cancel** stops after the current chunk and keeps the text so far.
- When finished: **Copy**, **Save…** (`.txt`, default name `<file name>.txt`,
  UTF-8) and **Transcribe Another**. Copy and Save write the text exactly as
  shown.
- Closing the window while a job runs asks "Stop transcribing?"; closing
  otherwise discards the transcript.
- The speaker models (about 22 MB: `Segmentation`, `FBank`, `Embedding`,
  `PldaRho` and the PLDA parameters from
  `FluidInference/speaker-diarization-coreml`) are downloaded the first time
  the switch is turned on, with progress in the window; the switch stays off
  if the download fails or is cancelled.

### Transcript format

- A paragraph is a run of consecutive words by one speaker with no pause of
  1.5 s or more inside it, and at most 60 s long; a longer run breaks at the
  first sentence end (`.`, `?`, `!`) after 60 s, or at 90 s regardless.
- Each paragraph starts with `[HH:MM:SS]` (the start of its first word,
  rounded down), followed by ` Speaker N` when speakers are identified, then
  the text on the next line. Paragraphs are separated by one blank line.
- Speakers are numbered from 1 in order of first appearance.
- With speakers off, or when the diarizer finds one speaker, there are no
  speaker labels.

### Dictation priority

- The file job transcribes one chunk at a time and, before each chunk, waits
  while a dictation session is in progress (`recording` or `finalizing`). The
  window shows "Paused while you dictate".
- Audio capture and the overlay start at once as today. The speech model runs
  one request at a time: if a file chunk is in flight when dictation starts,
  dictation's first streaming pass waits for it (about a second with Parakeet,
  possibly several with Whisper Large). Nothing typed is lost; the first live
  words arrive later.
- Changing or unloading the model during a job stops the job with "The
  transcription model changed" and keeps the text so far.

## Components

All new code is under `app/justscribe/`. Types that hold no reference to a
model or to AppKit are plain value types and are the unit-tested core.

### `Services/FileTranscription/TimedText.swift`

```swift
/// A word (or word-sized piece) with its place in the file, in seconds.
struct TimedWord: Equatable, Sendable { var text: String; var start: Double; var end: Double }
/// Who spoke between two times, from the diarizer.
struct SpeakerTurn: Equatable, Sendable { var speaker: String; var start: Double; var end: Double }
/// One paragraph of the transcript.
struct TranscriptParagraph: Equatable, Sendable { var start: Double; var speaker: Int?; var text: String }
```

### `Services/FileTranscription/AudioFileDecoder.swift`

- `init(url:) throws` opens the file with `AVAssetReader`, picking the first
  audio track; `duration: Double`.
- `func nextSamples(maxCount: Int) throws -> [Float]?` returns the next
  16 kHz mono `Float` samples, `nil` at the end. Nothing but the current
  buffer is held in memory.
- Errors: `notReadable`, `noAudioTrack`, `protectedContent`, each with a
  sentence for the window.

### `Services/FileTranscription/AudioChunker.swift`

- Pure. Accumulates samples and emits chunks of 20 to 30 s: it cuts at the
  quietest 100 ms window (lowest RMS) in the last 10 s, so a word is rarely
  split; the final chunk is whatever remains (at least one sample).
- Invariants, both tested: chunks concatenated equal the input; every chunk
  but the last is 20 to 30 s.
- Each chunk carries its start offset in seconds.

### `Services/TranscriptionService.swift` (changed)

- New: `func transcribeTimed(_ buffer: [Float], language: String?) async throws -> [TimedWord]`,
  times relative to the buffer. It does not touch `state` or
  `currentTranscription`.
  - Parakeet: `ASRResult.tokenTimings` merged into words (a token starting
    with the word-boundary marker begins a new word).
  - Whisper: `DecodingOptions.wordTimestamps = true`; each segment's `words`,
    or the segment itself as one piece when word timings are missing.
- New: an inference gate (an async lock) taken by every path that runs the
  model — streaming passes, the final pass and `transcribeTimed` — so the model
  never serves two requests at once. Requests are served in arrival order.
- New: `var modelGeneration: Int`, incremented on every load and unload, so a
  job can tell the model changed under it.

### `Services/FileTranscription/SpeakerDiarizationService.swift`

- `@MainActor @Observable` singleton wrapping `OfflineDiarizerManager`.
- `var isReady: Bool`, `var downloadProgress: Double?`,
  `func prepare() async throws` (download and load),
  `func turns(for url: URL, speakerCount: Int?) async throws -> [SpeakerTurn]`
  (uses the manager's disk-backed `process(_ url:)`; `speakerCount` sets
  `numSpeakers`).
- Models are stored where FluidAudio's Parakeet models already are (the app's
  container); deleting them is not offered in this version.

### `Services/FileTranscription/TranscriptBuilder.swift`

- Pure. `static func paragraphs(words: [TimedWord], turns: [SpeakerTurn]) -> [TranscriptParagraph]`
  and `static func text(_ paragraphs: [TranscriptParagraph]) -> String`.
- Speaker of a word: the turn with the largest overlap with the word's
  interval; with no overlap, the turn nearest in time; with no turns, none.
- Then the paragraph rules above. Speaker IDs from the diarizer are mapped to
  1, 2, … by first appearance. If only one speaker appears, labels are
  dropped.
- Incremental use: the job calls it with all words so far; paragraphs already
  shown never change except the last one, which may grow.

### `Services/FileTranscription/FileTranscriptionJob.swift`

- `@MainActor @Observable final class`. One instance per file.
- `enum Phase { idle, identifyingSpeakers, transcribing(Double), pausedForDictation(Double), finished, cancelled, failed(String) }`
  (downloading the speaker models is the window's concern, through
  `SpeakerDiarizationService.downloadProgress`, and happens before a job starts)
- `private(set) var paragraphs: [TranscriptParagraph]`, `var text: String`,
  `func start()`, `func cancel()`.
- Depends on three small protocols so tests can substitute fakes:
  `TimedTranscribing` (`transcribeTimed`, `modelGeneration`, `isModelLoaded`),
  `SpeakerTurnProviding` (`turns(for:speakerCount:)`) and `DictationActivity`
  (`var isDictating: Bool`, awaited by polling every 200 ms).
- Flow: optional speaker pass → loop { wait while dictating; read and chunk;
  `transcribeTimed`; shift times by the chunk offset; rebuild paragraphs;
  update progress } → finished.
- A failure in the speaker pass fails the job before transcription starts. A
  failure in a chunk stops the job as `failed`, keeping `paragraphs`.

### `AppDelegate.swift` (changed)

- Conforms to `DictationActivity` (`isDictating` is `sessionState != .idle`).
- Status-item menu: **Transcribe File…** after "Start Transcription".
- Owns a `FileTranscriptionWindowController`.

### `Views/FileTranscription/`

- `FileTranscriptionWindowController.swift`: an `NSWindow` (titled
  "Transcribe File", 560×520, resizable, remembered frame) hosting the SwiftUI
  view; shows, activates the app, and implements the close confirmation.
- `FileTranscriptionView.swift`: the drop zone, options, progress, transcript
  (selectable text in a scroll view that follows new text), and buttons.
  Follows the Settings window's visual style (`PillStyles`).

## Errors

| Situation | What the window says |
|---|---|
| No model loaded | "Choose a transcription model in Settings first" + Open Settings |
| File cannot be opened or decoded | "JustScribe can't read this file" |
| No audio track | "This file has no audio" |
| Protected (DRM) media | "This file is copy-protected and can't be transcribed" |
| Speaker model download fails | "Couldn't download the speaker model. Check your connection and try again"; switch returns to off |
| Speaker pass fails | "Couldn't identify speakers in this file"; offer **Transcribe Without Speakers** |
| A chunk fails | "Transcription stopped: <reason>"; text so far stays, Copy and Save work |
| Model changed during the job | "The transcription model changed"; text so far stays |
| Nothing recognised | "No speech was found in this file" |

## Privacy and the website

- The file is read in place; nothing is copied, uploaded or kept. The privacy
  policy's statements hold. Its list of downloads gains the speaker model
  (same host, Hugging Face).
- After release: the home page, `llms.txt` and the MacWhisper and Superwhisper
  comparison tables are updated ("File transcription: Yes, with timestamps and
  speakers"), and a guide page is added. This is a `web:` change made once the
  feature is in a published version.

## Testing

- `AudioChunker`: concatenation invariant; length bounds; a cut lands in a
  planted silence; a clip shorter than 20 s is one chunk; empty input yields
  none.
- `TranscriptBuilder`: overlap assignment; nearest turn for a word in a gap;
  paragraph breaks on speaker change, on a 1.5 s pause, at a sentence end
  after 60 s and at 90 s; numbering by first appearance; single speaker drops
  labels; no turns gives unlabelled paragraphs; timestamp formatting past one
  hour; earlier paragraphs are stable as words are appended.
- Token-to-word merging for Parakeet timings (pure helper).
- `AudioFileDecoder`: a WAV generated in the test (44.1 kHz stereo) decodes to
  16 kHz mono with the expected sample count within 1%; a text file and a
  missing file fail as `notReadable`. A video without audio (`noAudioTrack`) is
  checked by hand: producing one in a unit test needs a video encoder session.
- `FileTranscriptionJob` with fakes: progress reaches 1 and phase `finished`;
  times are shifted by chunk offsets; it does not call the transcriber while
  `isDictating` and resumes after; cancel keeps the text; a failing chunk
  gives `failed` with the text so far; a changed `modelGeneration` stops it.
- By hand before release: a two-speaker recording of a few minutes with
  Parakeet v3 and with a Whisper model; a video file; a long file (an hour)
  watching memory; dictating during a job.

## Out of scope

Subtitle export (SRT/VTT), renaming speakers, editing the transcript in the
window, several files or a queue, Finder "Open With", transcript history,
grammar correction of file transcripts, and deleting the speaker model.
