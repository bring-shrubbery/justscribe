# Dictation history — design

An opt-in record of past dictations: their text, and optionally their audio.
Both switches are off by default; nothing is kept until the user turns one on.
A History window lists past dictations, finds them by text, and lets the user
copy, paste, play and delete them. Everything stays inside the app's sandbox
container on the Mac.

## Decisions

| Question | Decision |
|---|---|
| Purpose | Find and reuse text; play back kept audio. No re-transcription, no editing. |
| Default | Off. Two switches: **Keep transcriptions** and **Keep audio recordings**; audio requires transcriptions. |
| Retention | Text until deleted. Audio until deleted or until the audio folder exceeds 1 GB, oldest first. |
| Scope | Dictations only. File transcripts stay as they are. |
| Storage | Files in the container: `History/index.json` and `History/audio/<id>.m4a`. No SwiftData. |

## Behaviour

### What is kept, and when

- At the end of a dictation session, after the final pass, grammar correction
  and the paste or typing, and only when the final text is not blank: a
  `DictationRecord` with `id` (UUID), `createdAt`, `text` (the final text, the
  same the user got), `durationSeconds` (the recording's), `modelID` (the
  unified model ID) and `language`, plus `audioFileName` when audio is kept.
- Cancelled sessions, the short-recording guard ("Recording too short") and
  sessions that end with no text keep nothing.
- The switches are read at the end of the session, so turning one on mid-
  dictation keeps that dictation. Turning one off keeps what exists; the
  Settings section says "Existing items are kept until you delete them."
- Audio is the session's 16 kHz mono buffer encoded to AAC (mono, 48 kbit/s,
  about 0.36 MB per minute) in an `.m4a`. The file is written and closed
  before the index entry is added, so the index never names a missing file.
  Encoding runs off the main actor; the record is added when it finishes.
  If encoding fails, the record is kept without audio.
- **Audio cap:** 1 GB, fixed. After each addition, while the audio folder's
  total exceeds the cap, the oldest record's audio is deleted and its
  `audioFileName` cleared; the text stays. Files in the audio folder that no
  record names are deleted at launch (leftovers from a crash).

### Settings → History

- **Keep transcriptions** switch; subtitle "Save the text of each dictation so
  you can find and reuse it later."
- **Keep audio recordings** switch, disabled while transcriptions are off (and
  turned off with it); subtitle "Also save the recording. Oldest recordings are
  removed once they pass 1 GB (about 45 hours)."
- "Existing items are kept until you delete them." under the switches, shown
  when either switch is off and history holds anything.
- **Delete All History…** button with a confirmation alert ("Delete all N
  dictations and their recordings? This cannot be undone."). Disabled when
  history is empty. Shows the item count and the audio folder's size.
- UserDefaults keys through `AppSettings`' dual-write:
  `historyKeepsTranscriptions` (Bool, default false),
  `historyKeepsAudio` (Bool, default false).

### History window

- "History…" in the status-item menu, after "Transcribe File…". An AppKit
  window ("History", 720×480, resizable, remembered frame) hosting SwiftUI,
  like the Transcribe File window.
- Left: a search field and a list, newest first. Each row: the time ("Today
  14:05", "Yesterday 09:12", else the date and time), the first line of the
  text truncated, the duration ("0:42"), and a waveform symbol when audio
  exists. Search matches case- and diacritic-insensitively on the text;
  empty search shows everything.
- Right: the selected record's full text (selectable), its date, duration,
  model and language, and buttons **Copy**, **Paste**, **Play** / **Stop**
  (only with audio), **Delete**.
  - **Paste** hides the window, activates the app that was frontmost when the
    window opened, waits for it to become active, and pastes once through
    `ClipboardService.paste(_:restorePrevious:)` with the same clipboard
    behaviour as dictation (restore when "Copy to Clipboard" is off). If no
    other app can be activated, it copies instead and says "Copied".
  - **Play** uses `AVAudioPlayer` on the `.m4a`; one player at a time; Stop
    when done or when another row is selected.
  - **Delete** removes the record and its audio, no confirmation (one item);
    the selection moves to the next row.
- Empty states: "History is off. Turn on Keep transcriptions in Settings to
  start keeping dictations." with an Open Settings button when the switch is
  off and there are no items; "No dictations yet." when on and empty; "No
  matches." for a search.
- Nothing is written when the window merely opens; opening does not touch the
  switches.

## Components

All under `app/justscribe/`. Pure types are `nonisolated`.

### `Models/DictationRecord.swift`

```swift
nonisolated struct DictationRecord: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var createdAt: Date
    var text: String
    var durationSeconds: Double
    var modelID: String
    var language: String?
    var audioFileName: String?
}
/// The on-disk index. `version` lets a later format change migrate.
nonisolated struct HistoryIndex: Codable, Equatable, Sendable {
    var version: Int   // 1
    var records: [DictationRecord]
}
```

### `Services/History/HistoryStore.swift`

- `@MainActor @Observable final class HistoryStore`, `static let shared`,
  `init(directory: URL)` (tests pass a temp directory; the app passes
  `Application Support/<bundle id>/History` inside the container).
- `private(set) var records: [DictationRecord]` (newest first),
  `var audioBytes: Int` (folder total, kept current), `static let audioCap = 1_000_000_000`.
- `func load()` at launch: reads the index (a missing or unreadable index is
  an empty history; an unreadable one is renamed `index.json.broken` rather
  than overwritten), then removes audio files no record names.
- `func add(text:durationSeconds:modelID:language:audio: [Float]?) async`:
  encodes audio (if any) through `HistoryAudioWriter`, then appends the record,
  saves the index, enforces the cap.
- `func delete(_ id: UUID)`, `func deleteAll()`, `func search(_ query: String) -> [DictationRecord]`,
  `func audioURL(for record: DictationRecord) -> URL?`.
- Index writes are atomic (`Data.write(options: .atomic)`), on the main actor
  (the index is small).
- Enforcing the cap is a pure function tested on its own:
  `static func audioToRemove(records: [DictationRecord], sizes: [String: Int], cap: Int) -> [String]`
  returns the oldest records' audio file names whose removal brings the total
  under the cap.

### `Services/History/HistoryAudioWriter.swift`

- `nonisolated enum HistoryAudioWriter` with
  `@concurrent static func write(samples: [Float], to url: URL) async throws`:
  an `AVAudioFile` with AAC settings (`kAudioFormatMPEG4AAC`, 16 kHz, mono,
  `AVEncoderBitRateKey` 48_000) written from an `AVAudioPCMBuffer`. Deletes a
  partial file on failure.
- Decoding for tests: `AudioFileDecoder.open` (already in the app) reads the
  `.m4a` back and the sample count is checked within 2%.

### `Services/History/HistoryPolicy.swift`

- Pure, tested: `static func shouldKeep(text:keepTranscriptions:keepAudio:) -> (text: Bool, audio: Bool)`:
  text when `keepTranscriptions` and the text is not blank; audio only when
  text is kept and `keepAudio`.
- `static func rowTitle(_ text: String) -> String` (first non-empty line,
  trimmed) and `static func rowTime(_ date: Date, now: Date, calendar:) -> String`.

### `AppDelegate.swift` (changed)

- At the end of `stopRecordingAndFinalize`, after the paste/copy and before
  the overlay's completed state is replaced, reads the two keys, asks
  `HistoryPolicy.shouldKeep`, takes the audio buffer before `clearBuffer()`
  when audio is kept, and calls `HistoryStore.shared.add(...)` in a `Task`
  (the session returns to idle without waiting for the encode).
- Menu item "History…"; owns a `HistoryWindowController`.
- `HistoryStore.shared.load()` at launch.

### `Views/Settings/Sections/HistorySettingsSection.swift`

The two switches, the note, the count and size, and Delete All with its
alert. Between "Updates" and "Support JustScribe" in `SettingsView`.

### `Views/History/`

`HistoryWindowController.swift` (window, frontmost-app capture on `show()`,
Paste's activate-then-paste), `HistoryView.swift` (search, list, detail),
`HistoryPlayback.swift` (`@Observable` wrapper over `AVAudioPlayer`:
`play(url)`, `stop()`, `isPlaying`).

## Privacy

`web/src/pages/privacy.md` gains a "History" section: off by default; what
each switch keeps and where (inside the App's container on your Mac); that
nothing leaves the Mac; that Delete All History removes everything; that
turning a switch off keeps existing items. The "What the App does not
collect" list gains "— unless you turn on History, in which case the App
keeps them on your Mac only". `llms.txt` and the home page's privacy FAQ get
one sentence each. This is a `web:` change made with the release.

## Error handling

| Situation | Behaviour |
|---|---|
| Index unreadable at launch | Renamed `index.json.broken`; history starts empty; a line in Settings: "A damaged history index was set aside." |
| Audio encode fails | Record kept without audio; logged. |
| Disk full on index write | The write throws; the record is dropped from memory too; logged. Dictation itself is unaffected. |
| Audio file missing for a record | Row shows no audio; Play hidden. |
| Paste target cannot be activated | Falls back to Copy and says so. |

## Testing

- `HistoryPolicy`: all combinations of the two switches and blank text; row
  title and time formatting (today, yesterday, older; midnight boundaries).
- `HistoryStore` on a temp directory: add text-only; add with audio writes
  the file before the index; delete removes the file; deleteAll empties the
  folder; search (case, diacritics, empty query); the cap removes oldest
  audio first and keeps the text; load after an unreadable index sets it
  aside; load removes an orphaned audio file; a record whose audio file is
  gone reports no audio URL.
- `HistoryAudioWriter`: a 3 s tone round-trips through `AudioFileDecoder`
  within 2% of 48,000 samples.
- By hand: both switches in every combination across several dictations;
  the window's search, Copy, Paste into another app, Play, Delete, Delete
  All; the 1 GB cap with a lowered cap in a debug build; the privacy page.

## Out of scope

Re-transcription, editing, export, retention periods, pausing history for a
sensitive dictation, sync, file transcripts in history, encryption beyond the
container and FileVault.
