# Apple Foundation Models Grammar Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Apple's on-device foundation model (`FoundationModels`) as a grammar correction backend that needs no download, and make it the default selection.

**Architecture:** `GrammarCorrectionService` becomes a thin router over a `GrammarBackend` protocol with two implementations — `AppleFoundationGrammarBackend` (new) and `MLXGrammarBackend` (extracted from the current service body). The service's public surface and the recording flow in `AppDelegate` are unchanged apart from one method rename.

**Tech Stack:** Swift 5 language mode, SwiftUI + AppKit, SwiftData, `FoundationModels` (macOS 26.0+), MLXLLM/MLXLMCommon, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-07-25-apple-foundation-grammar-design.md`

## Global Constraints

- Deployment target is **macOS 26.2**; `FoundationModels` is `macOS 26.0+`, so **no `@available` guards are needed anywhere**.
- Every new file needs the **GPL-3.0 header**. `IDETemplateMacros.plist` only fires for files created inside Xcode, so it must be pasted in by hand. Copy the header verbatim from `justscribe/Models/GrammarCorrectionModel.swift`, changing only the filename line.
- The Xcode project uses **file-system-synchronized groups**. New files under `justscribe/` and `justscribeTests/` are picked up automatically — **never hand-edit `project.pbxproj`**.
- The app target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; the **test target does not**. Any type a test touches synchronously must be declared `nonisolated`, or the call is main-actor-isolated from a nonisolated context — a warning in Swift 5 mode, an error under Swift 6. This applies to `GrammarTextChunker`, `GrammarCorrectionModel`, `GrammarBackendAvailability`, `AppSettings.normalizedGrammarModelID`, and the availability-mapping function. Existing types that are *not* being made `nonisolated` (such as `RAMEstimate`) must instead be reached from a `@MainActor`-annotated test. `nonisolated` on `enum` and `struct` declarations was compile-checked under these exact flags while writing this plan.
- Build: `xcodebuild -scheme justscribe -configuration Debug build`
- Test: `xcodebuild -scheme justscribe -destination 'platform=macOS' test`
- SourceKit frequently reports bogus "Cannot find type" errors for cross-file references in this project. **Verify with an actual `xcodebuild` before chasing them.**
- Commit after every task.

## Pre-verified facts (do not re-derive)

These were checked against `MacOSX26.5.sdk` with Xcode 26.6 while writing this plan:

- `SystemLanguageModel.default.availability` returns `Availability = .available | .unavailable(UnavailableReason)`, where `UnavailableReason = .deviceNotEligible | .appleIntelligenceNotEnabled | .modelNotReady`.
- `LanguageModelSession(instructions: String?)`, `.prewarm()`, and `respond(to: String, options: GenerationOptions) async throws -> Response<String>` (use `.content`) all exist as written below.
- `GenerationOptions(sampling: .greedy)` compiles.
- `LanguageModelSession` is **not** `Sendable`, and `Response<Content>` is **not** `Sendable`. The timeout helper therefore must return `String` (extract `.content` **inside** the closure), not `Response`.
- The SF Symbol `apple.intelligence` exists on macOS 26.
- No code outside `Services/GrammarCorrectionService.swift` references `GrammarCorrectionError`, so it is safe to replace with `GrammarBackendError`.
- **On this development Mac, Apple Intelligence is currently turned off** (`live: appleIntelligenceNotEnabled`). Manual verification of the happy path in Task 9 requires enabling it in System Settings first.

## File Structure

| File | Responsibility |
|---|---|
| `justscribe/Services/Grammar/GrammarTextChunker.swift` | Pure sentence-boundary splitting. No framework deps. |
| `justscribe/Services/Grammar/GrammarBackend.swift` | Protocol, availability enum, error enum, timeout helper. |
| `justscribe/Services/Grammar/AppleFoundationGrammarBackend.swift` | FoundationModels implementation. |
| `justscribe/Services/Grammar/MLXGrammarBackend.swift` | MLX implementation, extracted verbatim. |
| `justscribe/Services/GrammarCorrectionService.swift` | Router + `@Observable` state for the UI. |
| `justscribe/Models/GrammarCorrectionModel.swift` | Catalog with a backend discriminator. |
| `justscribe/Models/AppSettings.swift` | Default model ID + empty-string normalization. |
| `justscribe/Models/RAMEstimate.swift` | Handle the now-optional RAM field. |
| `justscribe/Views/Settings/Sections/GrammarCorrectionSettingsSection.swift` | Two row types, selected by backend. |
| `justscribe/AppDelegate.swift` | One rename at one call site. |
| `justscribeTests/GrammarTextChunkerTests.swift` | Chunker tests. |
| `justscribeTests/GrammarBackendAvailabilityTests.swift` | Availability-mapping tests. |
| `justscribeTests/GrammarCorrectionModelTests.swift` | Catalog/default tests. |

---

### Task 1: GrammarTextChunker

Pure text splitting with one hard invariant: **joining the chunks reproduces the input exactly**. That invariant is what makes it safe to feed chunks through the model and reassemble them, because `ClipboardService.replaceTypedText(characterCount:withText:)` depends on the original character count.

**Files:**
- Create: `justscribe/Services/Grammar/GrammarTextChunker.swift`
- Test: `justscribeTests/GrammarTextChunkerTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `nonisolated enum GrammarTextChunker` with `static func chunks(_ text: String, maxLength: Int = 2000) -> [String]`.

- [ ] **Step 1: Write the failing test**

Create `justscribeTests/GrammarTextChunkerTests.swift` with the GPL-3.0 header, then:

```swift
import Testing
@testable import justscribe

struct GrammarTextChunkerTests {

    @Test func emptyTextYieldsNoChunks() {
        #expect(GrammarTextChunker.chunks("").isEmpty)
    }

    @Test func shortTextIsASingleChunk() {
        let text = "Hello there. How are you?"
        #expect(GrammarTextChunker.chunks(text, maxLength: 2000) == [text])
    }

    /// The load-bearing invariant: chunking never adds, drops, or reorders characters.
    @Test(arguments: [
        "",
        "   \n\n  ",
        "One sentence.",
        "Line one.\nLine two.\n\nLine three.",
        String(repeating: "This is a sentence. ", count: 40),
        String(repeating: "word ", count: 200),
        String(repeating: "x", count: 500),
        "Dr. Smith went to Washington. He arrived at 3 p.m. It was raining!  Then he left.",
    ])
    func joiningChunksReproducesTheInput(text: String) {
        #expect(GrammarTextChunker.chunks(text, maxLength: 100).joined() == text)
    }

    @Test func chunksRespectMaxLength() {
        let text = String(repeating: "This is a sentence. ", count: 40)
        for chunk in GrammarTextChunker.chunks(text, maxLength: 100) {
            #expect(chunk.count <= 100)
        }
    }

    @Test func oversizedSentenceIsSplitOnWordBoundaries() {
        let sentence = String(repeating: "alpha beta gamma ", count: 20) + "."
        let chunks = GrammarTextChunker.chunks(sentence, maxLength: 100)
        #expect(chunks.count > 1)
        #expect(chunks.joined() == sentence)
        for chunk in chunks {
            #expect(chunk.count <= 100)
        }
    }

    @Test func singleWordLongerThanMaxIsEmittedWhole() {
        let word = String(repeating: "x", count: 250)
        #expect(GrammarTextChunker.chunks(word, maxLength: 100) == [word])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests/GrammarTextChunkerTests
```

Expected: build failure, `cannot find 'GrammarTextChunker' in scope`.

- [ ] **Step 3: Write the implementation**

Create `justscribe/Services/Grammar/GrammarTextChunker.swift` with the GPL-3.0 header, then the code below. This exact implementation was compiled and run against all seven tests above while writing this plan — all passed. Do not "improve" the `pieces(in:options:)` helper; the gap-filling around `range` is what guarantees the round-trip invariant.

```swift
import Foundation

/// Splits text into chunks small enough for a model with a limited context window,
/// breaking on sentence boundaries where possible.
///
/// Invariant: `chunks(t).joined() == t` for every input. Whitespace between
/// sentences is carried inside whichever chunk it falls in, never dropped.
nonisolated enum GrammarTextChunker {

    static func chunks(_ text: String, maxLength: Int = 2000) -> [String] {
        guard !text.isEmpty else { return [] }
        guard text.count > maxLength else { return [text] }

        var result: [String] = []
        var current = ""

        for sentence in pieces(in: text, options: .bySentences) {
            if sentence.count > maxLength {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
                result.append(contentsOf: splitOnWords(sentence, maxLength: maxLength))
                continue
            }
            if !current.isEmpty && current.count + sentence.count > maxLength {
                result.append(current)
                current = sentence
            } else {
                current += sentence
            }
        }

        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Split a single oversized sentence on word boundaries. A word longer than
    /// `maxLength` is emitted as its own oversized chunk rather than broken mid-word.
    private static func splitOnWords(_ text: String, maxLength: Int) -> [String] {
        var result: [String] = []
        var current = ""
        for word in pieces(in: text, options: .byWords) {
            if !current.isEmpty && current.count + word.count > maxLength {
                result.append(current)
                current = word
            } else {
                current += word
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Enumerate substrings, emitting the gaps between them as their own pieces so
    /// that concatenating the result reproduces the input exactly.
    private static func pieces(in text: String, options: String.EnumerationOptions) -> [String] {
        var out: [String] = []
        var covered = text.startIndex
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: options) { _, range, _, _ in
            if covered < range.lowerBound {
                out.append(String(text[covered..<range.lowerBound]))
            }
            out.append(String(text[range]))
            covered = range.upperBound
        }
        if covered < text.endIndex {
            out.append(String(text[covered...]))
        }
        return out.isEmpty ? [text] : out
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests/GrammarTextChunkerTests
```

Expected: `** TEST SUCCEEDED **`, 13 tests passing (the 8-argument parameterized test counts as 8).

- [ ] **Step 5: Commit**

```bash
git add justscribe/Services/Grammar/GrammarTextChunker.swift justscribeTests/GrammarTextChunkerTests.swift
git commit -m "Add sentence-boundary text chunker for grammar correction"
```

---

### Task 2: Model catalog with a backend discriminator

**Files:**
- Modify: `justscribe/Models/GrammarCorrectionModel.swift`
- Modify: `justscribe/Models/RAMEstimate.swift:36`
- Test: `justscribeTests/GrammarCorrectionModelTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `nonisolated enum GrammarModelBackend { case apple, mlx }`; `GrammarCorrectionModel` with added `backend: GrammarModelBackend` and now-optional `hubID: String?`, `approximateSize: String?`, `approximateRAM: String?`, `approximateRAMInMB: Int?`; `GrammarCorrectionModel.appleFoundation`; `GrammarCorrectionModel.defaultModelID -> String` (value `"apple-foundation"`).

- [ ] **Step 1: Write the failing test**

Create `justscribeTests/GrammarCorrectionModelTests.swift` with the GPL-3.0 header, then:

```swift
import Testing
@testable import justscribe

struct GrammarCorrectionModelTests {

    @Test func appleModelIsTheDefault() {
        #expect(GrammarCorrectionModel.defaultModelID == GrammarCorrectionModel.appleFoundation.id)
    }

    @Test func appleModelIsListedFirst() {
        #expect(GrammarCorrectionModel.allModels.first?.id == GrammarCorrectionModel.appleFoundation.id)
    }

    @Test func appleModelNeedsNoDownload() {
        let model = GrammarCorrectionModel.appleFoundation
        #expect(model.backend == .apple)
        #expect(model.hubID == nil)
        #expect(model.approximateRAMInMB == nil)
    }

    @Test func llamaModelKeepsItsExistingIdentifier() {
        // Persisted in UserDefaults by existing installs; changing it would silently
        // reset their selection.
        let model = GrammarCorrectionModel.llama3_1_8b_4bit
        #expect(model.id == "llama-3.1-8b-instruct-4bit")
        #expect(model.backend == .mlx)
        #expect(model.hubID == "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit")
    }

    @Test func lookupFindsBothModels() {
        #expect(GrammarCorrectionModel.model(forID: "apple-foundation") != nil)
        #expect(GrammarCorrectionModel.model(forID: "llama-3.1-8b-instruct-4bit") != nil)
        #expect(GrammarCorrectionModel.model(forID: "nope") == nil)
    }

    // `RAMEstimate` is a plain enum in the app target, so it inherits that target's
    // MainActor default isolation. This test must hop to the main actor to call it.
    @MainActor
    @Test func appleModelContributesNothingToTheRAMEstimate() {
        // The OS owns the foundation model's memory, not us.
        let total = RAMEstimate.totalMB(
            transcriptionModelID: "",
            grammarEnabled: true,
            grammarModelID: "apple-foundation"
        )
        #expect(total == 0)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests/GrammarCorrectionModelTests
```

Expected: build failure, `type 'GrammarCorrectionModel' has no member 'appleFoundation'`.

- [ ] **Step 3: Rewrite the model catalog**

Replace everything below the GPL-3.0 header in `justscribe/Models/GrammarCorrectionModel.swift` with:

```swift
import Foundation

/// Which engine runs a given grammar correction model.
nonisolated enum GrammarModelBackend: Hashable {
    /// Apple's on-device foundation model, part of macOS. No download, no RAM budget.
    case apple
    /// An MLX model downloaded from Hugging Face and held in our process.
    case mlx
}

nonisolated struct GrammarCorrectionModel: Identifiable, Hashable {
    let id: String
    let displayName: String
    let provider: String
    let backend: GrammarModelBackend
    /// Hugging Face repo. `nil` for backends that don't download anything.
    let hubID: String?
    let approximateSize: String?
    let approximateRAM: String?
    /// Contribution to our own RAM budget. `nil` when the OS owns the memory.
    let approximateRAMInMB: Int?

    static let appleFoundation = GrammarCorrectionModel(
        id: "apple-foundation",
        displayName: "Apple Intelligence",
        provider: "Built into macOS",
        backend: .apple,
        hubID: nil,
        approximateSize: nil,
        approximateRAM: nil,
        approximateRAMInMB: nil
    )

    static let llama3_1_8b_4bit = GrammarCorrectionModel(
        id: "llama-3.1-8b-instruct-4bit",
        displayName: "Llama 3.1 8B Instruct",
        provider: "Meta (4-bit MLX)",
        backend: .mlx,
        hubID: "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit",
        approximateSize: "~4.6 GB",
        approximateRAM: "~5 GB",
        approximateRAMInMB: 5120
    )

    static let allModels: [GrammarCorrectionModel] = [.appleFoundation, .llama3_1_8b_4bit]

    /// Selected for new installs: no download, no RAM cost.
    static let defaultModelID = appleFoundation.id

    static func model(forID id: String) -> GrammarCorrectionModel? {
        allModels.first { $0.id == id }
    }
}
```

- [ ] **Step 4: Fix the RAM estimate for the optional field**

In `justscribe/Models/RAMEstimate.swift`, change line 36 from:

```swift
            total += model.approximateRAMInMB
```

to:

```swift
            total += model.approximateRAMInMB ?? 0
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
xcodebuild -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests/GrammarCorrectionModelTests
```

Expected: `** TEST SUCCEEDED **`, 6 tests passing.

Note: the app target will still fail to build if you run a full build now, because `GrammarCorrectionService.swift` uses `model.hubID` as a non-optional. That is fixed in Task 4. Only run the `-only-testing` command at this step.

- [ ] **Step 6: Commit**

```bash
git add justscribe/Models/GrammarCorrectionModel.swift justscribe/Models/RAMEstimate.swift justscribeTests/GrammarCorrectionModelTests.swift
git commit -m "Add backend discriminator and Apple entry to grammar model catalog"
```

---

### Task 3: Backend protocol, availability, errors, timeout helper

**Files:**
- Create: `justscribe/Services/Grammar/GrammarBackend.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `nonisolated enum GrammarBackendAvailability: Equatable { case available; case requiresDownload; case unavailable(reason: String, settingsURL: URL?) }`
  - `nonisolated enum GrammarBackendError: LocalizedError { case notReady, modelNotFound, notDeletable, unavailable(String), timeout }`
  - `@MainActor protocol GrammarBackend: AnyObject` with `var modelID: String { get }`, `var availability: GrammarBackendAvailability { get }`, `var isReady: Bool { get }`, `func prepare(onProgress: @escaping @MainActor (Double) -> Void) async throws`, `func correct(_ text: String, language: String?) async throws -> String`, `func unload()`
  - `func withGrammarTimeout<T: Sendable>(_ duration: Duration, operation: @escaping @Sendable () async throws -> T) async throws -> T`

- [ ] **Step 1: Write the file**

Create `justscribe/Services/Grammar/GrammarBackend.swift` with the GPL-3.0 header, then:

```swift
import Foundation

/// Whether a grammar model can be used right now, and if not, why.
nonisolated enum GrammarBackendAvailability: Equatable {
    /// Usable immediately.
    case available
    /// Usable, but the weights have to be downloaded first.
    case requiresDownload
    /// Not usable. `reason` is user-facing; `settingsURL` opens the pane that fixes it.
    case unavailable(reason: String, settingsURL: URL?)
}

nonisolated enum GrammarBackendError: LocalizedError {
    case notReady
    case modelNotFound
    case notDeletable
    case unavailable(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "Grammar correction model is not loaded."
        case .modelNotFound:
            return "Grammar correction model not found."
        case .notDeletable:
            return "This model is part of macOS and cannot be deleted."
        case .unavailable(let reason):
            return reason
        case .timeout:
            return "Grammar correction timed out."
        }
    }
}

/// One grammar correction engine. Implementations are singletons owned by
/// `GrammarCorrectionService`, which is the only thing that talks to them.
@MainActor
protocol GrammarBackend: AnyObject {
    /// The `GrammarCorrectionModel.id` this backend serves.
    var modelID: String { get }
    var availability: GrammarBackendAvailability { get }
    /// True once `prepare` has succeeded and `correct` can be called.
    var isReady: Bool { get }

    /// Download if necessary and get ready to correct. `onProgress` receives 0...1.
    func prepare(onProgress: @escaping @MainActor (Double) -> Void) async throws
    func correct(_ text: String, language: String?) async throws -> String
    func unload()
}

/// Race `operation` against a timer so a wedged model can't hang a dictation.
///
/// `T` must be `Sendable`; in practice callers pass `String`. Note that
/// `LanguageModelSession.Response` is *not* `Sendable`, so extract `.content`
/// inside the closure rather than returning the response itself.
func withGrammarTimeout<T: Sendable>(
    _ duration: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw GrammarBackendError.timeout
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
```

- [ ] **Step 2: Verify it builds**

```bash
xcodebuild -scheme justscribe -configuration Debug build 2>&1 | tail -20
```

Expected: still fails on `GrammarCorrectionService.swift` because of Task 2's optional `hubID` — that is fine and expected. Confirm there are **no errors reported in `GrammarBackend.swift` itself**. Task 4 clears the remaining failure.

- [ ] **Step 3: Commit**

```bash
git add justscribe/Services/Grammar/GrammarBackend.swift
git commit -m "Add GrammarBackend protocol, availability and timeout helper"
```

---

### Task 4: Extract MLXGrammarBackend

Move the current service's body into a backend. **No behavior changes** — same disk probing, same `GenerateParameters`, same 30-second timeout, same log lines.

**Files:**
- Create: `justscribe/Services/Grammar/MLXGrammarBackend.swift`
- Modify: `justscribe/Services/GrammarCorrectionService.swift` (rewritten in Task 6; for now leave it alone)

**Interfaces:**
- Consumes: `GrammarBackend`, `GrammarBackendAvailability`, `GrammarBackendError`, `withGrammarTimeout` (Task 3); `GrammarCorrectionModel` (Task 2).
- Produces: `@MainActor final class MLXGrammarBackend: GrammarBackend` with these members beyond the protocol: `var downloadedModelIDs: Set<String>`, `func refreshDownloadedModels()`, `func delete(modelID: String) throws`.

- [ ] **Step 1: Write the file**

Create `justscribe/Services/Grammar/MLXGrammarBackend.swift` with the GPL-3.0 header, then:

```swift
import Foundation
import MLXLLM
import MLXLMCommon

/// Grammar correction via an MLX model downloaded from Hugging Face and held in
/// our own process. Serves `GrammarCorrectionModel.llama3_1_8b_4bit`.
@MainActor
final class MLXGrammarBackend: GrammarBackend {

    let modelID = GrammarCorrectionModel.llama3_1_8b_4bit.id

    private static let systemPrompt = """
        You are a grammar correction assistant. Fix grammar, spelling, and punctuation errors \
        in the following text. Preserve the original meaning and tone. Output ONLY the corrected \
        text with no explanations, no quotes, and no additional formatting.
        """

    private static let requestTimeout: Duration = .seconds(30)

    private(set) var isReady = false
    private(set) var downloadedModelIDs: Set<String> = []

    private var modelContainer: ModelContainer?
    private var chatSession: ChatSession?

    init() {
        refreshDownloadedModels()
    }

    var availability: GrammarBackendAvailability {
        guard let model = GrammarCorrectionModel.model(forID: modelID), let hubID = model.hubID else {
            return .unavailable(reason: "Unknown model.", settingsURL: nil)
        }
        return Self.isModelOnDisk(hubID: hubID) ? .available : .requiresDownload
    }

    // MARK: - Discovery

    func refreshDownloadedModels() {
        var found: Set<String> = []
        for model in GrammarCorrectionModel.allModels where model.backend == .mlx {
            if let hubID = model.hubID, Self.isModelOnDisk(hubID: hubID) {
                found.insert(model.id)
            }
        }
        downloadedModelIDs = found
    }

    /// Probe the on-disk MLX/HuggingFace cache for the given hub ID.
    /// MLX-LM stores model files under `Library/Caches/models/<org>/<repo>/`.
    private static func isModelOnDisk(hubID: String) -> Bool {
        let fileManager = FileManager.default
        guard let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return false
        }
        let modelDir = cachesDir.appendingPathComponent("models").appendingPathComponent(hubID)
        let config = modelDir.appendingPathComponent("config.json")
        let weights = modelDir.appendingPathComponent("model.safetensors")
        let weightsIndex = modelDir.appendingPathComponent("model.safetensors.index.json")
        return fileManager.fileExists(atPath: config.path)
            && (fileManager.fileExists(atPath: weights.path) || fileManager.fileExists(atPath: weightsIndex.path))
    }

    // MARK: - Lifecycle

    func prepare(onProgress: @escaping @MainActor (Double) -> Void) async throws {
        guard let model = GrammarCorrectionModel.model(forID: modelID), let hubID = model.hubID else {
            throw GrammarBackendError.modelNotFound
        }

        let configuration = ModelConfiguration(id: hubID)
        let container = try await loadModelContainer(configuration: configuration) { progress in
            Task { @MainActor in
                onProgress(progress.fractionCompleted)
            }
        }

        modelContainer = container
        chatSession = ChatSession(
            container,
            instructions: Self.systemPrompt,
            generateParameters: GenerateParameters(maxTokens: 2048, temperature: 0.1)
        )
        isReady = true
        refreshDownloadedModels()
    }

    /// Delete the on-disk files for a downloaded model. Unloads first if it is active.
    func delete(modelID: String) throws {
        guard let model = GrammarCorrectionModel.model(forID: modelID), let hubID = model.hubID else {
            throw GrammarBackendError.modelNotFound
        }

        if self.modelID == modelID && isReady {
            unload()
        }

        let fileManager = FileManager.default
        guard let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }
        let modelDir = cachesDir.appendingPathComponent("models").appendingPathComponent(hubID)
        if fileManager.fileExists(atPath: modelDir.path) {
            try fileManager.removeItem(at: modelDir)
            print("Deleted grammar correction model at: \(modelDir.path)")
        }

        refreshDownloadedModels()
    }

    func unload() {
        chatSession = nil
        modelContainer = nil
        isReady = false
    }

    // MARK: - Correction

    func correct(_ text: String, language: String?) async throws -> String {
        guard let session = chatSession else {
            throw GrammarBackendError.notReady
        }

        // Clear previous conversation to avoid context buildup
        await session.clear()

        let prompt: String
        if let language, !language.isEmpty, language != "en" {
            prompt = "Language: \(language). Text: \(text)"
        } else {
            prompt = text
        }

        let corrected = try await withGrammarTimeout(Self.requestTimeout) {
            try await session.respond(to: prompt)
        }
        return corrected.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 2: Verify it builds**

```bash
xcodebuild -scheme justscribe -configuration Debug build 2>&1 | tail -20
```

Expected: still fails inside `GrammarCorrectionService.swift` (untouched, still uses non-optional `hubID`). Confirm **no errors in `MLXGrammarBackend.swift`**.

If the compiler rejects the `withGrammarTimeout` call because `ChatSession` is not `Sendable`, replace that call with the inline task group that the original `correctGrammar` used — that shape already compiles in this project:

```swift
        let corrected = try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await session.respond(to: prompt) }
            group.addTask {
                try await Task.sleep(for: Self.requestTimeout)
                throw GrammarBackendError.timeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
```

- [ ] **Step 3: Commit**

```bash
git add justscribe/Services/Grammar/MLXGrammarBackend.swift
git commit -m "Extract MLX grammar correction into MLXGrammarBackend"
```

---

### Task 5: AppleFoundationGrammarBackend

**Files:**
- Create: `justscribe/Services/Grammar/AppleFoundationGrammarBackend.swift`
- Test: `justscribeTests/GrammarBackendAvailabilityTests.swift`

**Interfaces:**
- Consumes: `GrammarBackend`, `GrammarBackendAvailability`, `GrammarBackendError`, `withGrammarTimeout` (Task 3); `GrammarTextChunker` (Task 1); `GrammarCorrectionModel` (Task 2).
- Produces: `@MainActor final class AppleFoundationGrammarBackend: GrammarBackend`, plus two `nonisolated static` members that exist so they can be tested without Apple Intelligence hardware: `static func availability(for: SystemLanguageModel.Availability) -> GrammarBackendAvailability` and `static func reapplyPadding(from original: String, to corrected: String) -> String`.

- [ ] **Step 1: Write the failing test**

Create `justscribeTests/GrammarBackendAvailabilityTests.swift` with the GPL-3.0 header, then:

```swift
import FoundationModels
import Testing
@testable import justscribe

struct GrammarBackendAvailabilityTests {

    @Test func availableMapsToAvailable() {
        #expect(AppleFoundationGrammarBackend.availability(for: .available) == .available)
    }

    @Test func ineligibleDeviceHasNoSettingsLink() {
        // Nothing the user can do in System Settings, so don't offer a button.
        let result = AppleFoundationGrammarBackend.availability(for: .unavailable(.deviceNotEligible))
        guard case .unavailable(let reason, let url) = result else {
            Issue.record("expected .unavailable, got \(result)")
            return
        }
        #expect(!reason.isEmpty)
        #expect(url == nil)
    }

    @Test func disabledIntelligenceOffersASettingsLink() {
        let result = AppleFoundationGrammarBackend.availability(for: .unavailable(.appleIntelligenceNotEnabled))
        guard case .unavailable(let reason, let url) = result else {
            Issue.record("expected .unavailable, got \(result)")
            return
        }
        #expect(!reason.isEmpty)
        #expect(url != nil)
    }

    @Test func modelNotReadyOffersASettingsLink() {
        let result = AppleFoundationGrammarBackend.availability(for: .unavailable(.modelNotReady))
        guard case .unavailable(let reason, let url) = result else {
            Issue.record("expected .unavailable, got \(result)")
            return
        }
        #expect(!reason.isEmpty)
        #expect(url != nil)
    }

    @Test func paddingIsRestoredAroundCorrectedText() {
        // Chunks are trimmed before generation; rejoining must reproduce the spacing.
        let restored = AppleFoundationGrammarBackend.reapplyPadding(from: "  hi there.  ", to: "Hi there.")
        #expect(restored == "  Hi there.  ")
    }

    @Test func paddingIsANoOpWhenThereIsNone() {
        #expect(AppleFoundationGrammarBackend.reapplyPadding(from: "hi", to: "Hi") == "Hi")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests/GrammarBackendAvailabilityTests
```

Expected: build failure, `cannot find 'AppleFoundationGrammarBackend' in scope`.

- [ ] **Step 3: Write the implementation**

Create `justscribe/Services/Grammar/AppleFoundationGrammarBackend.swift` with the GPL-3.0 header, then:

```swift
import Foundation
import FoundationModels

/// Grammar correction via Apple's on-device foundation model. Part of macOS:
/// nothing to download, and the OS owns the memory.
@MainActor
final class AppleFoundationGrammarBackend: GrammarBackend {

    let modelID = GrammarCorrectionModel.appleFoundation.id

    /// Text at or below this length goes through in a single request. The model's
    /// context window is ~4096 tokens shared between prompt and response.
    private static let singleShotLimit = 4000
    private static let chunkLength = 2000
    private static let requestTimeout: Duration = .seconds(20)

    private static let instructions = """
        You are a grammar correction assistant. Fix grammar, spelling, and punctuation errors \
        in the following text. Preserve the original meaning and tone. Output ONLY the corrected \
        text with no explanations, no quotes, and no additional formatting.
        """

    /// Apple Intelligence & Siri pane.
    nonisolated static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.Siri-Settings.extension"
    )

    private(set) var isReady = false

    var availability: GrammarBackendAvailability {
        Self.availability(for: SystemLanguageModel.default.availability)
    }

    /// Pure mapping, split out so it can be tested without eligible hardware.
    nonisolated static func availability(
        for modelAvailability: SystemLanguageModel.Availability
    ) -> GrammarBackendAvailability {
        switch modelAvailability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable(
                reason: "Apple Intelligence isn't supported on this Mac.",
                settingsURL: nil
            )
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(
                reason: "Turn on Apple Intelligence in System Settings.",
                settingsURL: settingsURL
            )
        case .unavailable(.modelNotReady):
            return .unavailable(
                reason: "macOS is still downloading the model. Try again shortly.",
                settingsURL: settingsURL
            )
        @unknown default:
            return .unavailable(
                reason: "Apple Intelligence isn't available right now.",
                settingsURL: nil
            )
        }
    }

    // MARK: - Lifecycle

    func prepare(onProgress: @escaping @MainActor (Double) -> Void) async throws {
        guard case .available = availability else {
            throw GrammarBackendError.unavailable(
                availability.unavailableReason ?? "Apple Intelligence isn't available."
            )
        }
        // Nothing to download; just warm the model so the first correction isn't slow.
        makeSession().prewarm()
        isReady = true
        onProgress(1.0)
    }

    func unload() {
        isReady = false
    }

    // MARK: - Correction

    func correct(_ text: String, language: String?) async throws -> String {
        guard isReady else { throw GrammarBackendError.notReady }

        if text.count <= Self.singleShotLimit {
            return try await correctOne(text, language: language)
        }

        var corrected: [String] = []
        for chunk in GrammarTextChunker.chunks(text, maxLength: Self.chunkLength) {
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                corrected.append(chunk)
                continue
            }
            do {
                let result = try await correctOne(trimmed, language: language)
                corrected.append(Self.reapplyPadding(from: chunk, to: result))
            } catch {
                // A refusal or timeout on one chunk shouldn't discard the corrections
                // around it — keep this chunk's original text and carry on.
                print("Grammar correction chunk failed, keeping original: \(error)")
                corrected.append(chunk)
            }
        }
        return corrected.joined()
    }

    // MARK: - Private

    private func makeSession() -> LanguageModelSession {
        LanguageModelSession(instructions: Self.instructions)
    }

    private func correctOne(_ text: String, language: String?) async throws -> String {
        let prompt: String
        if let language, !language.isEmpty, language != "en" {
            prompt = "Language: \(language). Text: \(text)"
        } else {
            prompt = text
        }

        // A fresh session per request keeps context from accumulating across dictations.
        // Extract `.content` inside the closure: `Response` is not Sendable, `String` is.
        let session = makeSession()
        let corrected = try await withGrammarTimeout(Self.requestTimeout) {
            try await session.respond(
                to: prompt,
                options: GenerationOptions(sampling: .greedy)
            ).content
        }
        return corrected.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Restore the whitespace trimmed off a chunk before generation, so rejoining
    /// the corrected chunks reproduces the original spacing.
    nonisolated static func reapplyPadding(from original: String, to corrected: String) -> String {
        let leading = original.prefix { $0.isWhitespace }
        let trailing = String(original.reversed().prefix { $0.isWhitespace }.reversed())
        return String(leading) + corrected + trailing
    }
}

private extension GrammarBackendAvailability {
    var unavailableReason: String? {
        if case .unavailable(let reason, _) = self { return reason }
        return nil
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests/GrammarBackendAvailabilityTests
```

Expected: `** TEST SUCCEEDED **`, 6 tests passing. These pass regardless of whether Apple Intelligence is enabled, because the mapping function takes the availability value as a parameter.

- [ ] **Step 5: Commit**

```bash
git add justscribe/Services/Grammar/AppleFoundationGrammarBackend.swift justscribeTests/GrammarBackendAvailabilityTests.swift
git commit -m "Add Apple Foundation Models grammar correction backend"
```

---

### Task 6: Turn GrammarCorrectionService into a router

This is the task that makes the app build again.

**Files:**
- Modify: `justscribe/Services/GrammarCorrectionService.swift` (full rewrite below the header)
- Modify: `justscribe/AppDelegate.swift:129`
- Modify: `justscribe/Views/Settings/Sections/GrammarCorrectionSettingsSection.swift:42` and `:66`

**Interfaces:**
- Consumes: all three backend files from Tasks 3–5.
- Produces: `GrammarCorrectionService.shared` keeping `isModelLoaded`, `isProcessing`, `isLoadingModel`, `loadProgress`, `loadedModelID`, `downloadedModels`, `activelyDownloadingModelID`, `loadModel(modelID:)`, `correctGrammar(_:language:)`, `deleteModel(modelID:)`, `unloadModel()`, `refreshDownloadedModels()`; **`isModelDownloaded(_:)` is replaced by `isReadyToUse(_:)`**; new `availability(for modelID: String) -> GrammarBackendAvailability`.

- [ ] **Step 1: Rewrite the service**

Replace everything below the GPL-3.0 header in `justscribe/Services/GrammarCorrectionService.swift` with:

```swift
import Foundation

/// Routes grammar correction to whichever backend serves the selected model.
/// Owns the observable state the settings UI binds to; the backends own the
/// engine-specific details.
@MainActor
@Observable
final class GrammarCorrectionService {
    static let shared = GrammarCorrectionService()

    private(set) var isModelLoaded = false
    private(set) var isProcessing = false
    private(set) var isLoadingModel = false
    private(set) var loadProgress: Double = 0
    private(set) var loadedModelID: String?
    /// MLX models present on disk. Always empty of Apple models — they aren't downloaded.
    private(set) var downloadedModels: Set<String> = []
    private(set) var activelyDownloadingModelID: String?

    private let appleBackend = AppleFoundationGrammarBackend()
    private let mlxBackend = MLXGrammarBackend()
    private var activeBackend: (any GrammarBackend)?

    private init() {
        refreshDownloadedModels()
    }

    // MARK: - Discovery

    private func backend(for modelID: String) -> (any GrammarBackend)? {
        guard let model = GrammarCorrectionModel.model(forID: modelID) else { return nil }
        switch model.backend {
        case .apple: return appleBackend
        case .mlx: return mlxBackend
        }
    }

    func refreshDownloadedModels() {
        mlxBackend.refreshDownloadedModels()
        downloadedModels = mlxBackend.downloadedModelIDs
    }

    /// Whether the model can be used right now with no further download. For MLX
    /// models that means the weights are on disk; for the Apple model it means
    /// Apple Intelligence is enabled and ready.
    func isReadyToUse(_ modelID: String) -> Bool {
        backend(for: modelID)?.availability == .available
    }

    func availability(for modelID: String) -> GrammarBackendAvailability {
        backend(for: modelID)?.availability
            ?? .unavailable(reason: "Unknown model.", settingsURL: nil)
    }

    // MARK: - Load

    func loadModel(modelID: String) async throws {
        guard let target = backend(for: modelID) else {
            throw GrammarBackendError.modelNotFound
        }

        if isModelLoaded && loadedModelID == modelID { return }
        if isLoadingModel { return }

        // If switching models, unload the previous one first.
        if isModelLoaded && loadedModelID != modelID {
            unloadModel()
        }

        isLoadingModel = true
        loadProgress = 0
        if target.availability == .requiresDownload {
            activelyDownloadingModelID = modelID
        }

        do {
            try await target.prepare { [weak self] fraction in
                self?.loadProgress = fraction
            }
            activeBackend = target
            isModelLoaded = true
            loadedModelID = modelID
            isLoadingModel = false
            activelyDownloadingModelID = nil
            loadProgress = 1.0
            refreshDownloadedModels()
            print("Grammar correction model loaded successfully: \(modelID)")
        } catch {
            isLoadingModel = false
            activelyDownloadingModelID = nil
            loadProgress = 0
            print("Failed to load grammar correction model \(modelID): \(error)")
            throw error
        }
    }

    /// Delete a downloaded model's files. Throws for models that are part of macOS.
    func deleteModel(modelID: String) throws {
        guard let target = backend(for: modelID) else {
            throw GrammarBackendError.modelNotFound
        }
        guard let mlx = target as? MLXGrammarBackend else {
            throw GrammarBackendError.notDeletable
        }
        if loadedModelID == modelID {
            unloadModel()
        }
        try mlx.delete(modelID: modelID)
        refreshDownloadedModels()
    }

    func unloadModel() {
        activeBackend?.unload()
        activeBackend = nil
        isModelLoaded = false
        isProcessing = false
        loadProgress = 0
        loadedModelID = nil
        print("Grammar correction model unloaded")
    }

    // MARK: - Correction

    func correctGrammar(_ text: String, language: String? = nil) async throws -> String {
        guard let backend = activeBackend else {
            throw GrammarBackendError.notReady
        }

        isProcessing = true
        defer { isProcessing = false }

        let corrected = try await backend.correct(text, language: language)
        print("Grammar correction: '\(text)' -> '\(corrected)'")
        return corrected
    }
}
```

- [ ] **Step 2: Update the three `isModelDownloaded` call sites**

In `justscribe/AppDelegate.swift`, line 129, change:

```swift
            guard GrammarCorrectionService.shared.isModelDownloaded(selectedID) else {
```

to:

```swift
            guard GrammarCorrectionService.shared.isReadyToUse(selectedID) else {
```

In `justscribe/Views/Settings/Sections/GrammarCorrectionSettingsSection.swift`, line 42, change:

```swift
                                      service.isModelDownloaded(settings.selectedGrammarModelID) {
```

to:

```swift
                                      service.isReadyToUse(settings.selectedGrammarModelID) {
```

and line 66, change:

```swift
    private var isDownloaded: Bool { service.isModelDownloaded(model.id) }
```

to:

```swift
    private var isDownloaded: Bool { service.isReadyToUse(model.id) }
```

Note: `AppDelegate.swift:98` also calls `isModelDownloaded`, but that is `ModelDownloadService` for **transcription** models. **Leave it alone.**

- [ ] **Step 3: Fix the optional subtitle in the existing MLX row**

Still in `GrammarCorrectionSettingsSection.swift`, the row body interpolates the now-optional size fields. Find:

```swift
                Text("\(model.provider) · \(model.approximateSize) · RAM \(model.approximateRAM)")
```

and replace with:

```swift
                Text(subtitleText)
```

then add this computed property to the same struct, just above `var body: some View`:

```swift
    private var subtitleText: String {
        [model.provider, model.approximateSize, model.approximateRAM.map { "RAM \($0)" }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
```

- [ ] **Step 4: Verify the whole app builds**

```bash
xcodebuild -scheme justscribe -configuration Debug build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`. This is the first task since Task 1 where a full build should pass.

- [ ] **Step 5: Run the full test suite**

```bash
xcodebuild -scheme justscribe -destination 'platform=macOS' test 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add justscribe/Services/GrammarCorrectionService.swift justscribe/AppDelegate.swift justscribe/Views/Settings/Sections/GrammarCorrectionSettingsSection.swift
git commit -m "Route grammar correction through pluggable backends"
```

---

### Task 7: Make the Apple model the default selection

**Files:**
- Modify: `justscribe/Models/AppSettings.swift:145` and `getOrCreate(in:)`
- Test: `justscribeTests/GrammarCorrectionModelTests.swift` (append)

**Interfaces:**
- Consumes: `GrammarCorrectionModel.defaultModelID` (Task 2).
- Produces: `AppSettings.normalizedGrammarModelID(_ stored: String) -> String`, a `nonisolated static` pure function so the migration rule is testable without a SwiftData container.

- [ ] **Step 1: Write the failing test**

Append to `justscribeTests/GrammarCorrectionModelTests.swift`, inside the struct:

```swift
    @Test func aBlankStoredSelectionBecomesTheAppleModel() {
        // Installs that never picked a model should land on the zero-cost default.
        #expect(AppSettings.normalizedGrammarModelID("") == "apple-foundation")
    }

    @Test func anExistingLlamaSelectionIsPreserved() {
        // Explicit user choices are never overridden.
        #expect(
            AppSettings.normalizedGrammarModelID("llama-3.1-8b-instruct-4bit")
                == "llama-3.1-8b-instruct-4bit"
        )
    }

    @Test func anUnknownStoredSelectionFallsBackToTheDefault() {
        #expect(AppSettings.normalizedGrammarModelID("deleted-model") == "apple-foundation")
    }
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests/GrammarCorrectionModelTests
```

Expected: build failure, `type 'AppSettings' has no member 'normalizedGrammarModelID'`.

- [ ] **Step 3: Change the default and add normalization**

In `justscribe/Models/AppSettings.swift`, change the property declaration at line 145 from:

```swift
    var selectedGrammarModelID: String = "" {
```

to:

```swift
    var selectedGrammarModelID: String = GrammarCorrectionModel.defaultModelID {
```

Then add this static function to `AppSettings`, immediately above `static func getOrCreate(in:)`:

```swift
    /// Resolve a stored grammar model selection. A blank or unrecognised value
    /// becomes the default; an explicit, still-valid choice is left alone.
    nonisolated static func normalizedGrammarModelID(_ stored: String) -> String {
        GrammarCorrectionModel.model(forID: stored) != nil
            ? stored
            : GrammarCorrectionModel.defaultModelID
    }
```

Finally, apply it in `getOrCreate(in:)`. Change:

```swift
        if let settings = existing?.first {
            // Sync to UserDefaults (didSet may not fire on SwiftData load)
            settings.syncToUserDefaults()
            return settings
        }
```

to:

```swift
        if let settings = existing?.first {
            // Existing rows keep whatever they stored, except a blank or stale
            // selection, which resolves to the current default.
            settings.selectedGrammarModelID =
                Self.normalizedGrammarModelID(settings.selectedGrammarModelID)
            // Sync to UserDefaults (didSet may not fire on SwiftData load)
            settings.syncToUserDefaults()
            return settings
        }
```

`syncToUserDefaults()` already writes `selectedGrammarModelID`, so no change is needed there. No new UserDefaults key is introduced.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests/GrammarCorrectionModelTests
```

Expected: `** TEST SUCCEEDED **`, 9 tests passing.

- [ ] **Step 5: Commit**

```bash
git add justscribe/Models/AppSettings.swift justscribeTests/GrammarCorrectionModelTests.swift
git commit -m "Default grammar correction to the Apple Intelligence model"
```

---

### Task 8: Settings UI for the Apple backend

**Files:**
- Modify: `justscribe/Views/Settings/Sections/GrammarCorrectionSettingsSection.swift`

**Interfaces:**
- Consumes: `GrammarCorrectionService.availability(for:)`, `GrammarBackendAvailability`, `GrammarModelBackend`.
- Produces: no new public API — `AvailableGrammarModelRow` is renamed `MLXGrammarModelRow`, and `AppleGrammarModelRow` is added.

- [ ] **Step 1: Add the AppKit import**

At the top of the file, change:

```swift
import SwiftUI
```

to:

```swift
import AppKit
import SwiftUI
```

`NSWorkspace` is needed for the System Settings deep link.

- [ ] **Step 2: Switch on the backend when building rows**

In `GrammarCorrectionSettingsSection.body`, replace:

```swift
                if settings.grammarCorrectionEnabled {
                    ForEach(GrammarCorrectionModel.allModels) { model in
                        Divider()
                        AvailableGrammarModelRow(model: model, settings: settings)
                    }
                }
```

with:

```swift
                if settings.grammarCorrectionEnabled {
                    ForEach(GrammarCorrectionModel.allModels) { model in
                        Divider()
                        switch model.backend {
                        case .apple:
                            AppleGrammarModelRow(model: model, settings: settings)
                        case .mlx:
                            MLXGrammarModelRow(model: model, settings: settings)
                        }
                    }
                }
```

- [ ] **Step 3: Rename the existing row**

Change the declaration:

```swift
private struct AvailableGrammarModelRow: View {
```

to:

```swift
private struct MLXGrammarModelRow: View {
```

Nothing else in that struct changes (Task 6 already updated its `isDownloaded` and subtitle).

- [ ] **Step 4: Add the Apple row**

Append to the end of the file:

```swift
private struct AppleGrammarModelRow: View {
    let model: GrammarCorrectionModel
    @Bindable var settings: AppSettings
    private var service: GrammarCorrectionService { GrammarCorrectionService.shared }

    private var availability: GrammarBackendAvailability { service.availability(for: model.id) }
    private var isLoaded: Bool { service.isModelLoaded && service.loadedModelID == model.id }
    private var isLoading: Bool { service.isLoadingModel && service.loadedModelID != model.id }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "apple.intelligence")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(.body)
                Text("\(model.provider) · No download")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                switch availability {
                case .available, .requiresDownload:
                    if isLoaded {
                        Label("Loaded", systemImage: "checkmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else if isLoading {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.6)
                            Text("Loading…").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                case .unavailable(let reason, _):
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            actionButton
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch availability {
        case .available, .requiresDownload:
            if isLoading {
                ProgressView().scaleEffect(0.7)
            } else if !isLoaded {
                Button {
                    settings.selectedGrammarModelID = model.id
                    Task { try? await service.loadModel(modelID: model.id) }
                } label: {
                    Label("Use", systemImage: "checkmark.circle")
                        .font(.callout)
                }
                .buttonStyle(.pill)
            }
        case .unavailable(_, let settingsURL):
            if let settingsURL {
                Button {
                    NSWorkspace.shared.open(settingsURL)
                } label: {
                    Label("Open Settings", systemImage: "gear")
                        .font(.callout)
                }
                .buttonStyle(.pill)
            }
        }
    }
}
```

- [ ] **Step 5: Verify the build**

```bash
xcodebuild -scheme justscribe -configuration Debug build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add justscribe/Views/Settings/Sections/GrammarCorrectionSettingsSection.swift
git commit -m "Add Apple Intelligence row to grammar correction settings"
```

---

### Task 9: Documentation and end-to-end verification

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Document the backend split**

In `CLAUDE.md`, find this paragraph under "Transcription providers":

```markdown
Grammar correction is a separate opt-in path: `GrammarCorrectionService` runs an MLX LLM
(Llama 3.1 8B 4-bit) downloaded on demand.
```

Replace it with:

```markdown
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
```

- [ ] **Step 2: Full clean build and test**

```bash
xcodebuild -scheme justscribe -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

```bash
xcodebuild -scheme justscribe -destination 'platform=macOS' test 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "Document the grammar correction backend split"
```

- [ ] **Step 4: Manual verification (requires a human at the keyboard)**

Report the results of each of these; do not claim the feature works without them.

1. Launch the app. Open Settings → Grammar Correction and enable the toggle.
2. **Unavailable path.** Apple Intelligence is currently **off** on this Mac, so the Apple Intelligence row should read "Turn on Apple Intelligence in System Settings." with an **Open Settings** button. Click it and confirm the Apple Intelligence & Siri pane opens. If the deep link does nothing under App Sandbox, change `AppleFoundationGrammarBackend.settingsURL` to `URL(string: "x-apple.systempreferences:")` and re-verify.
3. Turn on Apple Intelligence in System Settings and wait for the model to finish downloading.
4. Reopen Settings. The row should now offer **Use**. Click it; it should show "Loaded".
5. Dictate a sentence with deliberate errors ("me and him was going too the store yesterday") into TextEdit. Confirm the typed text is replaced with a corrected version.
6. Dictate a long passage (over 4,000 characters, roughly 12+ minutes of speech, or paste-and-retest by temporarily lowering `singleShotLimit` to 200) and confirm the result is coherent with no dropped or duplicated words at the chunk seams.
7. Toggle grammar correction off, dictate again, and confirm the raw transcription is typed and no correction runs.
8. Switch to the Llama row and confirm download / Use / delete still behave as before.

---

## Self-Review

**Spec coverage.** Every section of the spec maps to a task: model catalog → Task 2; backend protocol → Task 3; MLX extraction → Task 4; Apple backend and availability mapping → Task 5; chunking → Task 1; router and the `isReadyToUse` rename → Task 6; `AppSettings` default and normalization → Task 7; settings UI → Task 8; `CLAUDE.md` and manual verification → Task 9. The spec's `RAMEstimate` implication (the RAM field becoming optional) is covered in Task 2, Step 4.

**Placeholder scan.** No TBDs. Every code step contains complete code. The two "verify at implementation time" items from the spec were resolved *before* writing this plan — the SDK API surface is confirmed in "Pre-verified facts," and the settings URL has a concrete fallback in Task 9, Step 4.

**Type consistency.** `isReadyToUse(_:)` is used consistently from Task 6 onward. `GrammarBackendError` (not the deleted `GrammarCorrectionError`) is thrown everywhere. `prepare(onProgress:)`, `correct(_:language:)`, and `unload()` match between the protocol in Task 3 and both implementations. `GrammarTextChunker.chunks(_:maxLength:)` matches between Tasks 1 and 5. `AppSettings.normalizedGrammarModelID(_:)` matches between Tasks 7's test and implementation.

**Build-order check.** Tasks 1 and 2 leave the app target failing to build (`GrammarCorrectionService` still expects a non-optional `hubID`), which is why their verification steps use `-only-testing` and Tasks 3 and 4 explicitly expect a partial failure. Task 6 restores a green full build. This is called out inline in each affected step.
