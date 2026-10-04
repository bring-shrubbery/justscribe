# DynamicLanding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Our own Dynamic Island for macOS as a Swift package (`DynamicLanding`, sibling repo), with tested top-anchored geometry, hidden/compact/expanded states that morph in place, and JustScribe switched to it.

**Architecture:** A pure `IslandGeometry` turns `(state, screen metrics, style, configuration, content sizes)` into the island's rect, radii and slots; an `@Observable IslandModel` holds state and measured sizes and asks the geometry for the layout; `IslandView` draws the shape and content from that layout with every container top-aligned; `IslandPanelController` hosts the view in a non-activating `NSPanel` pinned to the screen's top edge and toggles mouse pass-through from the pointer's position. `DynamicLanding` is the small public façade. JustScribe's `OverlayManager` becomes an adapter over it.

**Tech Stack:** Swift package (`swift-tools-version: 6.0`, Swift 5 language mode, macOS 14+), SwiftUI + AppKit, Swift Testing; GitHub Actions `macos-latest` for the package; JustScribe (Xcode project, Swift 5 mode, default MainActor isolation).

**Spec:** `docs/superpowers/specs/2026-10-04-dynamic-landing-design.md` (in the JustScribe repo)

## Global Constraints

- Two repositories. **Package:** `/Users/antoni/Projects/dynamic-landing` (create it; GitHub `bring-shrubbery/dynamic-landing`, public, MIT) — work on `main` there (it is a new repo with no users). **App:** `/Users/antoni/Projects/justscribe` on branch `dynamic-landing`; never commit to the app's `main`, never push it (every code commit on `main` is released to users).
- Package commands (run in the package directory): `swift build`, `swift test`, `swift run DynamicLandingDemo` (never run the demo from a subagent — it shows UI on the maintainer's screen). App commands: `xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -configuration Debug build` and `… -destination 'platform=macOS' test -only-testing:justscribeTests`.
- Commit after each task with a user-readable subject in the package repo (its commits become its release notes) and in the app; end commit messages with a `Co-Authored-By:` trailer naming the model that did the work.
- Package concurrency: everything that touches AppKit/SwiftUI views is `@MainActor`; pure types (`ScreenMetrics`, `IslandLayout`, `IslandGeometry`, `IslandState`, `IslandConfiguration` and its enums) are `Sendable` value types with no actor isolation. `IslandConfiguration.animation` is a SwiftUI `Animation` (Sendable).
- Invariants the geometry tests pin for every state/style/screen: `rect.maxY == frame.maxY` and `abs(rect.midX - frame.midX) < 0.5` (top edge pinned, centred); on a notched screen the island body is never narrower than the notch and the hidden state is the notch rect; on a notchless screen the hidden state has zero height. Default values exactly as the spec's `IslandConfiguration`; compact slot padding 8 pt; a forced `.notch` style on a notchless screen uses a virtual notch of 180 × `compactHeight`; rect width/height clamp at half the screen.
- Every Swift file in the package starts with a short header comment (`// DynamicLanding — <file>`); JustScribe files keep the GPL header (copy from `app/justscribe/Services/History/HistoryPolicy.swift`).
- Tests never show windows: they use `IslandModel` and the pure types; `DynamicLanding(configuration:screen:)` with `screen: nil` and `presentsPanel: false` is the headless path. **Never add a test that opens an `AVAssetReader`** (app constraint).
- Do not run the JustScribe app from a subagent (it shares the installed copy's bundle ID and global hotkey).

## Review Focus

1. **A notchless external display**: compact and expanded islands hang from the top edge, centred, and the hidden→expanded morph keeps the top edge fixed — the bug this whole package exists to fix. Pinned in Task 2's invariant loop over a notchless `ScreenMetrics`.
2. **`show` while a `hide` is animating** (rapid repeat dictations): the hide is cancelled and the island morphs forward; there is never a second panel. Pinned in Task 4's state tests.
3. **Content wider than half the screen**: clamped, never off-screen. Pinned in Task 2.
4. **Clicks outside the island shape pass through** to the window beneath (a transparent half-screen panel must not swallow menu-bar clicks). Pinned by hand in Task 7 (hand check 4); the pass-through rule itself (`ignoresMouseEvents` unless the pointer is inside the island rect) is a pure function tested in Task 4.
5. **Compact slots never overlap the notch** on a notched screen. Pinned in Task 2.

---

### Task 1: Package scaffold, metrics, state and configuration

**Files (package repo, create):** `Package.swift`, `LICENSE`, `README.md`, `.gitignore`, `.github/workflows/ci.yml`, `Sources/DynamicLanding/IslandState.swift`, `Sources/DynamicLanding/IslandConfiguration.swift`, `Sources/DynamicLanding/Geometry/ScreenMetrics.swift`, `Sources/DynamicLandingDemo/main.swift` (placeholder), `Tests/DynamicLandingTests/ScreenMetricsTests.swift`

**Interfaces:**
- Produces: `IslandState`, `IslandStyle`, `IslandShadow`, `IslandBackground`, `IslandHoverBehavior`, `IslandConfiguration`, `ScreenMetrics` (`frame`, `notchSize`, `menuBarHeight`, `hasNotch`, `notchRect`, `init(frame:notchSize:menuBarHeight:)`, `@MainActor init(screen:)`).

- [ ] **Step 1: Create the repositories**

```bash
mkdir -p /Users/antoni/Projects/dynamic-landing && cd /Users/antoni/Projects/dynamic-landing && git init -q -b main
gh repo create bring-shrubbery/dynamic-landing --public --description "A Dynamic Island for macOS: a top-anchored floating island with compact and expanded states, flush with the notch or hanging from the top edge" --source . --remote origin
```

(If `gh repo create` refuses because the directory has no commits, run it after Step 7's first commit with `--push`.)

- [ ] **Step 2: Write `Package.swift`, `LICENSE`, `.gitignore`, `README.md`, CI**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DynamicLanding",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DynamicLanding", targets: ["DynamicLanding"]),
        .executable(name: "DynamicLandingDemo", targets: ["DynamicLandingDemo"]),
    ],
    targets: [
        .target(
            name: "DynamicLanding",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .executableTarget(name: "DynamicLandingDemo", dependencies: ["DynamicLanding"]),
        .testTarget(name: "DynamicLandingTests", dependencies: ["DynamicLanding"]),
    ],
    swiftLanguageModes: [.v5]
)
```

`LICENSE`: the MIT text with `Copyright (c) 2026 Quassum MB`. `.gitignore`: `.build/`, `.swiftpm/`, `*.xcodeproj`, `.DS_Store`, `Package.resolved` is **kept** (commit it once it exists). `README.md`:

```markdown
# DynamicLanding

A Dynamic Island for macOS. A floating island pinned to the top edge of a screen — flush with the
notch where there is one, a rounded pill hanging from the top edge where there is not — with
three states: hidden, compact (a leading and a trailing slot around the notch, like iOS Live
Activities) and expanded (any SwiftUI content). Every animation grows down from the top edge and
widens about the screen's centre; nothing ever inflates from the island's middle.

```swift
import DynamicLanding

let island = DynamicLanding(configuration: .init(style: .automatic))
await island.show(compactLeading: { Image(systemName: "waveform") }, trailing: { Text("0:12") })
await island.show(expanded: { ListeningCard() })   // morphs in place
await island.hide()
island.onTap = { … }
```

macOS 14+, no dependencies, MIT. Used by [JustScribe](https://justscribe.quassum.com).

`swift run DynamicLandingDemo` shows a menu-bar demo with every state and style.
```

`.github/workflows/ci.yml`:

```yaml
name: CI
on:
  push:
    branches: [main]
    tags: ["*"]
  pull_request:
jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: swift --version
      - run: swift build
      - run: swift test
```

- [ ] **Step 3: Write the failing test `ScreenMetricsTests.swift`**

```swift
import CoreGraphics
import Testing
@testable import DynamicLanding

struct ScreenMetricsTests {
    @Test func aNotchedScreenKnowsItsNotchRect() {
        let m = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchSize: CGSize(width: 200, height: 38), menuBarHeight: 38)
        #expect(m.hasNotch)
        #expect(m.notchRect == CGRect(x: 656, y: 944, width: 200, height: 38))
    }

    @Test func aNotchlessScreenHasNoNotchRect() {
        let m = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), notchSize: nil, menuBarHeight: 24)
        #expect(!m.hasNotch)
        #expect(m.notchRect == nil)
    }

    @Test func aSecondaryScreenOffsetIsRespected() {
        let m = ScreenMetrics(frame: CGRect(x: -2560, y: 200, width: 2560, height: 1440), notchSize: CGSize(width: 180, height: 32), menuBarHeight: 32)
        #expect(m.notchRect == CGRect(x: -2560 + 1190, y: 200 + 1440 - 32, width: 180, height: 32))
    }

    @Test func configurationDefaultsMatchTheSpec() {
        let c = IslandConfiguration()
        #expect(c.compactHeight == 32 && c.expandedTopInset == 8 && c.pillCornerRadius == 16)
        #expect(c.notchCornerRadii.top == 15 && c.notchCornerRadii.bottom == 20)
        #expect(c.shadow == .none && c.hoverBehavior.isEmpty)
        #expect(c.animationDuration == .milliseconds(350) && c.slotPadding == 8 && c.virtualNotchWidth == 180)
        #expect(c.contentPadding.top == 10 && c.contentPadding.leading == 16 && c.contentPadding.bottom == 12 && c.contentPadding.trailing == 16)
    }
}
```

- [ ] **Step 4: Run; it must fail to compile**

Run: `cd /Users/antoni/Projects/dynamic-landing && swift test 2>&1 | grep -E "error:|Test run|passed|failed" | head`
Expected: `error: cannot find 'ScreenMetrics' in scope` (or "no such module" before the sources exist — add the placeholder `main.swift` first: `print("DynamicLanding demo — replaced in Task 5")`).

- [ ] **Step 5: Write `IslandState.swift`, `IslandConfiguration.swift`, `ScreenMetrics.swift`**

```swift
// DynamicLanding — IslandState.swift
import Foundation

/// What the island is showing.
public enum IslandState: Equatable, Sendable {
    case hidden
    /// A leading and a trailing slot around the notch (or a narrow pill).
    case compact
    /// Rich content below the notch.
    case expanded
}
```

```swift
// DynamicLanding — IslandConfiguration.swift
import SwiftUI

/// How the island looks and moves. Defaults are the plain Dynamic Island: black, no shadow,
/// no bounce.
public struct IslandConfiguration: Sendable {
    public var style: IslandStyle = .automatic
    public var animation: Animation = .smooth(duration: 0.35)
    public var shadow: IslandShadow = .none
    public var background: IslandBackground = .black
    public var foreground: Color = .white
    public var contentPadding: EdgeInsets = EdgeInsets(top: 10, leading: 16, bottom: 12, trailing: 16)
    /// The compact island's height on a notchless screen (a notched screen uses the notch's).
    public var compactHeight: CGFloat = 32
    /// Space above expanded content on a notchless screen (a notched screen uses the notch's height).
    public var expandedTopInset: CGFloat = 8
    public var notchCornerRadii: (top: CGFloat, bottom: CGFloat) = (top: 15, bottom: 20)
    public var pillCornerRadius: CGFloat = 16
    public var hoverBehavior: IslandHoverBehavior = []
    /// Padding inside a compact slot, and the gap between the two slots on a pill.
    public var slotPadding: CGFloat = 8
    /// The notch a forced `.notch` style pretends to have on a notchless screen.
    public var virtualNotchWidth: CGFloat = 180
    /// How long `show`/`hide` wait for `animation` to finish (SwiftUI exposes no duration).
    public var animationDuration: Duration = .milliseconds(350)

    public init() {}
}

public enum IslandStyle: Equatable, Sendable {
    /// Notch look on a notched screen, pill on a notchless one.
    case automatic
    case notch(topCornerRadius: CGFloat, bottomCornerRadius: CGFloat)
    case pill(cornerRadius: CGFloat)
}

public enum IslandShadow: Equatable, Sendable {
    case none
    case soft(radius: CGFloat, opacity: CGFloat)
}

public enum IslandBackground: Sendable {
    case black
    case color(Color)
    case material(NSVisualEffectView.Material)
}

public struct IslandHoverBehavior: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    /// A pending `hide()` waits while the pointer is over the island.
    public static let keepVisible = IslandHoverBehavior(rawValue: 1 << 0)
    /// The island brightens slightly under the pointer.
    public static let highlight = IslandHoverBehavior(rawValue: 1 << 1)
}
```

```swift
// DynamicLanding — ScreenMetrics.swift
import AppKit

/// What the geometry needs to know about a screen: its frame (AppKit coordinates, origin
/// bottom-left), its notch if any, and the menu bar's height.
public struct ScreenMetrics: Equatable, Sendable {
    public var frame: CGRect
    public var notchSize: CGSize?
    public var menuBarHeight: CGFloat

    public init(frame: CGRect, notchSize: CGSize?, menuBarHeight: CGFloat) {
        self.frame = frame
        self.notchSize = notchSize
        self.menuBarHeight = menuBarHeight
    }

    /// Reads a live screen. The notch is the gap between the two auxiliary top areas.
    @MainActor
    public init(screen: NSScreen) {
        let frame = screen.frame
        var notch: CGSize?
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, screen.safeAreaInsets.top > 0 {
            notch = CGSize(width: frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
        }
        self.init(frame: frame, notchSize: notch, menuBarHeight: NSStatusBar.system.thickness)
    }

    public var hasNotch: Bool { notchSize != nil }

    /// The notch, in screen coordinates; nil on a notchless screen.
    public var notchRect: CGRect? {
        guard let notchSize else { return nil }
        return CGRect(x: frame.midX - notchSize.width / 2, y: frame.maxY - notchSize.height,
                      width: notchSize.width, height: notchSize.height)
    }
}
```

- [ ] **Step 6: Run; the four tests pass**

Run: `swift test 2>&1 | grep -E "error:|Test run|passed|failed" | tail -3`. Expected: `Test run with 4 tests passed`. If `IslandShadow` fails `Equatable` synthesis for `== .none`, it is `Equatable` already — check the test's `c.shadow == .none` compiles; if `IslandConfiguration`'s tuple property blocks `Sendable`, the tuple of `CGFloat`s is Sendable — keep it.

- [ ] **Step 7: Commit (and push)**

```bash
git add -A && git commit -m "Package scaffold: screen metrics, island states and configuration" && git push -u origin main
```

---

### Task 2: The geometry

**Files:** `Sources/DynamicLanding/Geometry/IslandGeometry.swift`; test `Tests/DynamicLandingTests/IslandGeometryTests.swift`

**Interfaces:**
- Consumes: Task 1.
- Produces: `IslandLayout { rect, topCornerRadius, bottomCornerRadius, leadingSlot, trailingSlot, contentRect, look }`, `IslandLook { notch, pill }`, `IslandGeometry.layout(state:metrics:configuration:compactSlotSizes:expandedContentSize:) -> IslandLayout`, `IslandGeometry.resolvedLook(style:metrics:) -> IslandLook`.

- [ ] **Step 1: Write the failing tests**

```swift
import CoreGraphics
import Testing
@testable import DynamicLanding

struct IslandGeometryTests {
    let notched = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchSize: CGSize(width: 200, height: 38), menuBarHeight: 38)
    let notchless = ScreenMetrics(frame: CGRect(x: 100, y: 50, width: 2560, height: 1440), notchSize: nil, menuBarHeight: 24)
    let slots = (leading: CGSize(width: 24, height: 20), trailing: CGSize(width: 40, height: 16))
    let content = CGSize(width: 260, height: 64)
    let styles: [IslandStyle] = [.automatic, .notch(topCornerRadius: 12, bottomCornerRadius: 18), .pill(cornerRadius: 14)]
    let states: [IslandState] = [.hidden, .compact, .expanded]

    private func layout(_ state: IslandState, _ metrics: ScreenMetrics, _ style: IslandStyle, content: CGSize? = nil) -> IslandLayout {
        var c = IslandConfiguration(); c.style = style
        return IslandGeometry.layout(state: state, metrics: metrics, configuration: c, compactSlotSizes: slots, expandedContentSize: content ?? self.content)
    }

    @Test func theTopEdgeIsPinnedAndTheIslandIsCentredEverywhere() {
        for metrics in [notched, notchless] {
            for style in styles {
                for state in states {
                    let l = layout(state, metrics, style)
                    #expect(l.rect.maxY == metrics.frame.maxY, "\(state) \(style) maxY")
                    #expect(abs(l.rect.midX - metrics.frame.midX) < 0.5, "\(state) \(style) midX")
                    #expect(l.rect.width <= metrics.frame.width / 2 && l.rect.height <= metrics.frame.height / 2)
                }
            }
        }
    }

    @Test func hiddenIsTheNotchOnANotchedScreenAndNothingOnANotchlessOne() {
        #expect(layout(.hidden, notched, .automatic).rect == notched.notchRect!)
        let none = layout(.hidden, notchless, .automatic).rect
        #expect(none.height == 0 && none.maxY == notchless.frame.maxY)
    }

    @Test func theNotchLookNeverGetsNarrowerThanTheNotch() {
        for state in states {
            let l = layout(state, notched, .automatic)
            #expect(l.look == .notch)
            #expect(l.rect.width >= notched.notchSize!.width, "\(state)")
            #expect(l.rect.height >= notched.notchSize!.height || state == .hidden)
        }
    }

    @Test func compactSlotsFlankTheNotchWithoutOverlappingIt() {
        let l = layout(.compact, notched, .automatic)
        let leading = try! #require(l.leadingSlot), trailing = try! #require(l.trailingSlot)
        // Island-local coordinates, top-left origin: the notch occupies the middle 200 pt.
        let notchMinX = (l.rect.width - 200) / 2, notchMaxX = notchMinX + 200
        #expect(leading.maxX == notchMinX - 8 && trailing.minX == notchMaxX + 8)
        #expect(leading.width == slots.leading.width && trailing.width == slots.trailing.width)
        #expect(l.rect.height == 38)
        #expect(l.rect.width == 200 + 2 * (15 + 40 + 8))   // the wider slot sets both sides
    }

    @Test func compactOnAPillIsTwoSlotsWithAGap() {
        let l = layout(.compact, notchless, .automatic)
        #expect(l.look == .pill)
        #expect(l.rect.height == 32)
        let leading = try! #require(l.leadingSlot), trailing = try! #require(l.trailingSlot)
        #expect(trailing.minX - leading.maxX == 8)
        #expect(l.rect.width == 24 + 40 + 3 * 8)
    }

    @Test func expandedWrapsTheContentBelowTheNotch() {
        let l = layout(.expanded, notched, .automatic)
        let rect = try! #require(l.contentRect)
        #expect(rect.minY == 38 + 10)
        #expect(rect.size == content)
        #expect(l.rect.height == 38 + 10 + 64 + 12)
        #expect(l.rect.width == 260 + 32 + 2 * 15)   // content, padding, and the two top flares
        #expect(abs(rect.midX - l.rect.width / 2) < 0.5)
    }

    @Test func expandedOnAPillHangsFromTheTopEdge() {
        let l = layout(.expanded, notchless, .automatic)
        #expect(l.contentRect?.minY == 8)
        #expect(l.rect.height == 8 + 64 + 12)
        #expect(l.rect.width == 260 + 32)
        #expect(l.topCornerRadius == 0 && l.bottomCornerRadius == 16)
    }

    @Test func aForcedNotchOnANotchlessScreenUsesAVirtualNotch() {
        let l = layout(.hidden, notchless, .notch(topCornerRadius: 12, bottomCornerRadius: 18))
        #expect(l.look == .notch)
        #expect(l.rect.width == 180 + 2 * 12 && l.rect.height == 32)
        #expect(l.topCornerRadius == 12 && l.bottomCornerRadius == 18)
    }

    @Test func aForcedPillOnANotchedScreenStillCoversTheNotch() {
        let l = layout(.compact, notched, .pill(cornerRadius: 14))
        #expect(l.look == .pill)
        #expect(l.rect.width >= 200 && l.rect.height >= 38)
    }

    @Test func oversizedContentIsClampedToHalfTheScreen() {
        let l = layout(.expanded, notchless, .automatic, content: CGSize(width: 5000, height: 5000))
        #expect(l.rect.width == notchless.frame.width / 2 && l.rect.height == notchless.frame.height / 2)
        #expect(l.rect.maxY == notchless.frame.maxY && abs(l.rect.midX - notchless.frame.midX) < 0.5)
    }
}
```

- [ ] **Step 2: Run; it must fail to compile**

Run: `swift test 2>&1 | grep -E "error:|Test run" | head -3`. Expected: `error: cannot find 'IslandGeometry' in scope`.

- [ ] **Step 3: Write `IslandGeometry.swift`**

```swift
// DynamicLanding — IslandGeometry.swift
import CoreGraphics

/// Which silhouette the island has.
public enum IslandLook: Equatable, Sendable {
    /// Flush with the notch: flared top corners, the body never narrower than the notch.
    case notch
    /// A rounded pill hanging from the top edge.
    case pill
}

/// Where everything goes for one state. `rect` is in screen coordinates (AppKit, origin
/// bottom-left); the slots and the content rect are island-local with a top-left origin.
public struct IslandLayout: Equatable, Sendable {
    public var rect: CGRect
    public var topCornerRadius: CGFloat
    public var bottomCornerRadius: CGFloat
    public var leadingSlot: CGRect?
    public var trailingSlot: CGRect?
    public var contentRect: CGRect?
    public var look: IslandLook
}

/// The island's layout maths. Pure: the same inputs always give the same layout, so the two
/// invariants that matter — top edge pinned to the screen's top, centred on the screen — are
/// tested rather than hoped for.
public enum IslandGeometry {

    public static func resolvedLook(style: IslandStyle, metrics: ScreenMetrics) -> IslandLook {
        switch style {
        case .automatic: metrics.hasNotch ? .notch : .pill
        case .notch: .notch
        case .pill: .pill
        }
    }

    public static func layout(
        state: IslandState, metrics: ScreenMetrics, configuration: IslandConfiguration,
        compactSlotSizes: (leading: CGSize, trailing: CGSize), expandedContentSize: CGSize
    ) -> IslandLayout {
        let look = resolvedLook(style: configuration.style, metrics: metrics)
        let radii = cornerRadii(for: look, style: configuration.style, configuration: configuration)
        let padding = configuration.slotPadding
        let frame = metrics.frame

        // The notch the island must cover: the real one, or a virtual one for a forced notch look.
        let notch: CGSize? = metrics.notchSize ?? (look == .notch
            ? CGSize(width: configuration.virtualNotchWidth, height: configuration.compactHeight) : nil)

        var width: CGFloat
        var height: CGFloat
        var leading: CGRect?
        var trailing: CGRect?
        var content: CGRect?

        switch (state, look) {
        case (.hidden, .notch):
            // The notch itself (a forced notch look adds the flares so the shape reads as a notch).
            let n = notch!
            width = metrics.hasNotch ? n.width : n.width + 2 * radii.top
            height = n.height
        case (.hidden, .pill):
            width = 0; height = 0
        case (.compact, .notch):
            // Both sides are as wide as the wider slot, so the island stays centred on the notch;
            // each slot hugs its side of the notch.
            let n = notch!
            height = n.height
            let side = max(compactSlotSizes.leading.width, compactSlotSizes.trailing.width) + padding
            width = n.width + 2 * (radii.top + side)
            let notchMinX = (width - n.width) / 2, notchMaxX = notchMinX + n.width
            leading = CGRect(x: notchMinX - padding - compactSlotSizes.leading.width, y: 0,
                             width: compactSlotSizes.leading.width, height: height)
            trailing = CGRect(x: notchMaxX + padding, y: 0, width: compactSlotSizes.trailing.width, height: height)
        case (.compact, .pill):
            height = max(configuration.compactHeight, metrics.notchSize?.height ?? 0)
            width = compactSlotSizes.leading.width + compactSlotSizes.trailing.width + 3 * padding
            width = max(width, metrics.notchSize?.width ?? 0)
            leading = CGRect(x: padding, y: 0, width: compactSlotSizes.leading.width, height: height)
            trailing = CGRect(x: width - padding - compactSlotSizes.trailing.width, y: 0,
                              width: compactSlotSizes.trailing.width, height: height)
        case (.expanded, .notch):
            let n = notch!
            let p = configuration.contentPadding
            let body = max(n.width, expandedContentSize.width + p.leading + p.trailing)
            width = body + 2 * radii.top
            height = n.height + p.top + expandedContentSize.height + p.bottom
            content = CGRect(x: (width - expandedContentSize.width) / 2, y: n.height + p.top,
                             width: expandedContentSize.width, height: expandedContentSize.height)
        case (.expanded, .pill):
            let p = configuration.contentPadding
            width = max(expandedContentSize.width + p.leading + p.trailing, metrics.notchSize?.width ?? 0)
            height = configuration.expandedTopInset + expandedContentSize.height + p.bottom
            if let n = metrics.notchSize { height = max(height, n.height) }
            content = CGRect(x: (width - expandedContentSize.width) / 2, y: configuration.expandedTopInset,
                             width: expandedContentSize.width, height: expandedContentSize.height)
        }

        // Never more than half the screen; the content clips.
        width = min(width, frame.width / 2)
        height = min(height, frame.height / 2)
        if var c = content {
            c.size.width = min(c.size.width, width); c.origin.x = (width - c.size.width) / 2
            c.size.height = max(0, min(c.size.height, height - c.origin.y)); content = c
        }

        let rect = CGRect(x: frame.midX - width / 2, y: frame.maxY - height, width: width, height: height)
        return IslandLayout(rect: rect, topCornerRadius: radii.top, bottomCornerRadius: radii.bottom,
                            leadingSlot: leading, trailingSlot: trailing, contentRect: content, look: look)
    }

    private static func cornerRadii(for look: IslandLook, style: IslandStyle, configuration: IslandConfiguration) -> (top: CGFloat, bottom: CGFloat) {
        switch (look, style) {
        case (.notch, .notch(let top, let bottom)): (top, bottom)
        case (.notch, _): configuration.notchCornerRadii
        case (.pill, .pill(let radius)): (0, radius)
        case (.pill, _): (0, configuration.pillCornerRadius)
        }
    }
}
```

- [ ] **Step 4: Run; the ten tests pass**

Run: `swift test 2>&1 | grep -E "error:|Test run|failed" | tail -4`. Expected: all pass. If `theNotchLookNeverGetsNarrowerThanTheNotch` fails on the hidden state's height, note the test allows `state == .hidden` there. If a `#require` inside a non-throwing test fails to compile, mark those test functions `throws` and drop the `try!`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Island geometry: top-anchored, centred layouts for hidden, compact and expanded on notched and notchless screens"
```

---

### Task 3: Shape and view

**Files:** `Sources/DynamicLanding/Views/IslandShape.swift`, `Sources/DynamicLanding/Views/SizeReader.swift`, `Sources/DynamicLanding/Views/IslandView.swift`, `Sources/DynamicLanding/IslandModel.swift`; test `Tests/DynamicLandingTests/IslandShapeTests.swift`

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces: `IslandShape(look:topCornerRadius:bottomCornerRadius:)` (`Shape`, `Animatable` radii), `IslandModel` (`@MainActor @Observable`: `state`, `metrics`, `configuration`, `compactLeading/compactTrailing/expandedContent: AnyView`, `leadingSize/trailingSize/contentSize`, `layout`, `isHovering`, `onTap`, `setContent(_:)`, `setState(_:)`), `IslandView(model:)`.

- [ ] **Step 1: Write the failing test**

```swift
import SwiftUI
import Testing
@testable import DynamicLanding

struct IslandShapeTests {
    @Test func theNotchShapeFlaresAtTheTopAndStaysInsideItsRect() {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 80)
        let path = IslandShape(look: .notch, topCornerRadius: 15, bottomCornerRadius: 20).path(in: rect)
        let bounds = path.boundingRect
        #expect(bounds.minX >= -0.01 && bounds.maxX <= 300.01 && bounds.minY >= -0.01 && bounds.maxY <= 80.01)
        // The top edge spans the full width (the flares meet the menu bar); the body is narrower.
        #expect(path.contains(CGPoint(x: 1, y: 0.5)) && path.contains(CGPoint(x: 299, y: 0.5)))
        #expect(!path.contains(CGPoint(x: 1, y: 40)) && path.contains(CGPoint(x: 150, y: 40)))
    }

    @Test func thePillShapeIsFlatOnTopAndRoundedBelow() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 60)
        let path = IslandShape(look: .pill, topCornerRadius: 0, bottomCornerRadius: 16).path(in: rect)
        #expect(path.contains(CGPoint(x: 0.5, y: 0.5)) && path.contains(CGPoint(x: 199.5, y: 0.5)))
        #expect(!path.contains(CGPoint(x: 1, y: 59)) && path.contains(CGPoint(x: 100, y: 59)))
    }

    @MainActor @Test func theModelLaysOutFromItsInputs() {
        let metrics = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchSize: CGSize(width: 200, height: 38), menuBarHeight: 38)
        let model = IslandModel(configuration: IslandConfiguration(), metrics: metrics)
        #expect(model.layout.rect == metrics.notchRect)
        model.contentSize = CGSize(width: 100, height: 50)
        model.setState(.expanded)
        #expect(model.layout.rect.height == 38 + 10 + 50 + 12)
        #expect(model.layout.rect.maxY == 982)
    }
}
```

- [ ] **Step 2: Run; it must fail to compile**

Run: `swift test 2>&1 | grep -E "error:" | head -2`. Expected: `cannot find 'IslandShape' in scope`.

- [ ] **Step 3: Write `IslandShape.swift`**

```swift
// DynamicLanding — IslandShape.swift
import SwiftUI

/// The island's silhouette. Notch look: the top corners flare outward so the shape meets the
/// menu bar like the real notch; pill look: flat on top, rounded below.
public struct IslandShape: Shape {
    public var look: IslandLook
    public var topCornerRadius: CGFloat
    public var bottomCornerRadius: CGFloat

    public init(look: IslandLook, topCornerRadius: CGFloat, bottomCornerRadius: CGFloat) {
        self.look = look
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set { topCornerRadius = newValue.first; bottomCornerRadius = newValue.second }
    }

    public func path(in rect: CGRect) -> Path {
        switch look {
        case .pill:
            return Path(roundedRect: rect, cornerRadii: RectangleCornerRadii(
                topLeading: 0, bottomLeading: bottomCornerRadius, bottomTrailing: bottomCornerRadius, topTrailing: 0))
        case .notch:
            let top = min(topCornerRadius, rect.width / 4, rect.height / 2)
            let bottom = min(bottomCornerRadius, (rect.width - 2 * top) / 2, max(0, rect.height - top))
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.minY + top), control: CGPoint(x: rect.minX + top, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
            p.addQuadCurve(to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY), control: CGPoint(x: rect.minX + top, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
            p.addQuadCurve(to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom), control: CGPoint(x: rect.maxX - top, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - top, y: rect.minY))
            p.closeSubpath()
            return p
        }
    }
}
```

- [ ] **Step 4: Write `SizeReader.swift` and `IslandModel.swift`**

```swift
// DynamicLanding — SizeReader.swift
import SwiftUI

/// Reports a view's laid-out size to the model, so the shape can follow the content.
struct SizeReader: ViewModifier {
    let onChange: @MainActor (CGSize) -> Void
    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGSize.self, of: \.size) { size in onChange(size) }
    }
}

extension View {
    func readSize(_ onChange: @escaping @MainActor (CGSize) -> Void) -> some View {
        modifier(SizeReader(onChange: onChange))
    }
}
```

```swift
// DynamicLanding — IslandModel.swift
import SwiftUI

/// The island's state and measured content sizes; the layout is derived from them. The view
/// observes it, the controller drives it. No window here, so tests can use it directly.
@MainActor @Observable
public final class IslandModel {
    public private(set) var state: IslandState = .hidden
    public var metrics: ScreenMetrics
    public var configuration: IslandConfiguration
    var compactLeading: AnyView = AnyView(EmptyView())
    var compactTrailing: AnyView = AnyView(EmptyView())
    var expandedContent: AnyView = AnyView(EmptyView())
    var leadingSize: CGSize = .zero
    var trailingSize: CGSize = .zero
    var contentSize: CGSize = .zero
    var isHovering = false
    /// Bumped on every content change so a same-state replacement still fades.
    var contentGeneration = 0
    public var onTap: (() -> Void)?

    public init(configuration: IslandConfiguration, metrics: ScreenMetrics) {
        self.configuration = configuration
        self.metrics = metrics
    }

    public var layout: IslandLayout {
        IslandGeometry.layout(state: state, metrics: metrics, configuration: configuration,
                              compactSlotSizes: (leadingSize, trailingSize), expandedContentSize: contentSize)
    }

    public func setState(_ new: IslandState) { state = new }

    func setCompact(leading: AnyView, trailing: AnyView) {
        compactLeading = leading; compactTrailing = trailing; contentGeneration += 1
    }

    func setExpanded(_ content: AnyView) {
        expandedContent = content; contentGeneration += 1
    }
}
```

- [ ] **Step 5: Write `IslandView.swift`**

```swift
// DynamicLanding — IslandView.swift
import SwiftUI

/// Draws the island from the model's layout. Every container is top-aligned and the shape's
/// frame comes from the geometry, so growth is always downward from the top edge and
/// symmetric about the centre — on any screen.
struct IslandView: View {
    @Bindable var model: IslandModel

    var body: some View {
        let layout = model.layout
        let config = model.configuration
        ZStack(alignment: .top) {
            IslandShape(look: layout.look, topCornerRadius: layout.topCornerRadius, bottomCornerRadius: layout.bottomCornerRadius)
                .fill(backgroundStyle(config.background))
                .overlay(hoverHighlight(config))
                .shadow(color: shadowColor(config.shadow), radius: shadowRadius(config.shadow))
                .frame(width: layout.rect.width, height: layout.rect.height, alignment: .top)
                .contentShape(IslandShape(look: layout.look, topCornerRadius: layout.topCornerRadius, bottomCornerRadius: layout.bottomCornerRadius))
                .onTapGesture { model.onTap?() }

            content(layout: layout)
                .frame(width: layout.rect.width, height: layout.rect.height, alignment: .topLeading)
                .clipped()
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(config.foreground)
        .animation(config.animation, value: layout)
        .animation(config.animation, value: model.isHovering)
        // Measure the content where it is laid out at its natural size; the shape follows.
        .background(measurers)
    }

    @ViewBuilder
    private func content(layout: IslandLayout) -> some View {
        ZStack(alignment: .topLeading) {
            if model.state == .compact, let l = layout.leadingSlot, let t = layout.trailingSlot {
                model.compactLeading.frame(width: l.width, height: l.height).offset(x: l.minX, y: l.minY)
                model.compactTrailing.frame(width: t.width, height: t.height).offset(x: t.minX, y: t.minY)
            }
            if model.state == .expanded, let c = layout.contentRect {
                model.expandedContent.frame(width: c.width, height: c.height, alignment: .topLeading).offset(x: c.minX, y: c.minY)
            }
        }
        .id(model.contentGeneration)
        .transition(.opacity)
    }

    /// Hidden copies at natural size, measured so the geometry knows the content's size before
    /// the visible copy is constrained to it.
    private var measurers: some View {
        ZStack(alignment: .topLeading) {
            model.compactLeading.fixedSize().readSize { model.leadingSize = $0 }
            model.compactTrailing.fixedSize().readSize { model.trailingSize = $0 }
            model.expandedContent.fixedSize().readSize { model.contentSize = $0 }
        }
        .opacity(0)
        .allowsHitTesting(false)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func backgroundStyle(_ background: IslandBackground) -> AnyShapeStyle {
        switch background {
        case .black: AnyShapeStyle(Color.black)
        case .color(let color): AnyShapeStyle(color)
        case .material: AnyShapeStyle(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private func hoverHighlight(_ config: IslandConfiguration) -> some View {
        if config.hoverBehavior.contains(.highlight), model.isHovering {
            IslandShape(look: model.layout.look, topCornerRadius: model.layout.topCornerRadius, bottomCornerRadius: model.layout.bottomCornerRadius)
                .fill(Color.white.opacity(0.08))
        }
    }

    private func shadowColor(_ shadow: IslandShadow) -> Color {
        if case .soft(_, let opacity) = shadow { return .black.opacity(opacity) }
        return .clear
    }

    private func shadowRadius(_ shadow: IslandShadow) -> CGFloat {
        if case .soft(let radius, _) = shadow { return radius }
        return 0
    }
}
```

`IslandLayout` must be `Equatable` for `.animation(value:)` — it is. SwiftUI animates the `.frame(width:height:)` of the shape between layouts; because the shape is inside a top-aligned `ZStack` inside a top-aligned frame, the top edge stays put while it grows. `IslandBackground.material` uses `.ultraThinMaterial` here (an `NSVisualEffectView` wrapper is not worth it in v0.1; the enum case keeps the API shape).

- [ ] **Step 6: Run; all tests pass; the demo still builds**

Run: `swift build 2>&1 | grep -E "error:|warning:" | head; swift test 2>&1 | grep -E "error:|Test run|failed" | tail -3`. Expected: no errors, `Test run with 17 tests passed`. If `Path(roundedRect:cornerRadii:)` is unavailable on macOS 14, use `UnevenRoundedRectangle(cornerRadii:).path(in:)`.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "Island shape, model and view: the shape follows the geometry, top-aligned at every level"
```

---

### Task 4: The panel, pass-through, and the public API

**Files:** `Sources/DynamicLanding/Panel/IslandPanel.swift`, `Sources/DynamicLanding/Panel/IslandPanelController.swift`, `Sources/DynamicLanding/DynamicLanding.swift`, `Sources/DynamicLanding/Panel/MousePassThrough.swift`; test `Tests/DynamicLandingTests/DynamicLandingStateTests.swift`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: `DynamicLanding` (`@MainActor @Observable`): `init(configuration:screen:presentsPanel:)`, `state`, `configuration`, `onTap`, `isVisible`, `show(compactLeading:trailing:) async`, `show(expanded:) async`, `hide() async`, `model` (public read-only, for tests and advanced use); `MousePassThrough.shouldIgnoreMouse(pointer:islandRect:) -> Bool`.

- [ ] **Step 1: Write the failing tests**

```swift
import SwiftUI
import Testing
@testable import DynamicLanding

@MainActor
struct DynamicLandingStateTests {
    private func island() -> DynamicLanding {
        let metrics = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchSize: CGSize(width: 200, height: 38), menuBarHeight: 38)
        var c = IslandConfiguration(); c.animation = .linear(duration: 0.01); c.animationDuration = .milliseconds(10)
        return DynamicLanding(configuration: c, metrics: metrics, presentsPanel: false)
    }

    @Test func showingCompactThenExpandedMorphsInPlace() async {
        let i = island()
        #expect(i.state == .hidden && !i.isVisible)
        await i.show(compactLeading: { Text("L") }, trailing: { Text("T") })
        #expect(i.state == .compact && i.isVisible)
        await i.show(expanded: { Text("Big") })
        #expect(i.state == .expanded)
        await i.hide()
        #expect(i.state == .hidden && !i.isVisible)
    }

    @Test func aShowDuringAHideCancelsTheHide() async {
        let i = island()
        await i.show(expanded: { Text("A") })
        let hiding = Task { await i.hide() }
        await i.show(expanded: { Text("B") })
        await hiding.value
        #expect(i.state == .expanded)
    }

    @Test func hidingWhenHiddenIsANoOp() async {
        let i = island()
        await i.hide()
        #expect(i.state == .hidden)
    }

    @Test func replacingContentInTheSameStateBumpsTheGeneration() async {
        let i = island()
        await i.show(expanded: { Text("A") })
        let g = i.model.contentGeneration
        await i.show(expanded: { Text("B") })
        #expect(i.model.contentGeneration == g + 1 && i.state == .expanded)
    }

    @Test func keepVisibleDelaysTheHideWhileHovering() async {
        let i = island()
        i.configuration.hoverBehavior = [.keepVisible]
        await i.show(expanded: { Text("A") })
        i.model.isHovering = true
        let hiding = Task { await i.hide() }
        try? await Task.sleep(for: .milliseconds(150))
        #expect(i.state == .expanded)       // still up while hovered
        i.model.isHovering = false
        await hiding.value
        #expect(i.state == .hidden)
    }

    @Test func mousePassThroughFollowsThePointer() {
        let rect = CGRect(x: 600, y: 900, width: 300, height: 80)
        #expect(MousePassThrough.shouldIgnoreMouse(pointer: CGPoint(x: 100, y: 100), islandRect: rect))
        #expect(!MousePassThrough.shouldIgnoreMouse(pointer: CGPoint(x: 700, y: 950), islandRect: rect))
        #expect(MousePassThrough.shouldIgnoreMouse(pointer: CGPoint(x: 700, y: 950), islandRect: .zero))
    }
}
```

- [ ] **Step 2: Run; it must fail to compile**

Run: `swift test 2>&1 | grep -E "error:" | head -2`. Expected: `cannot find 'DynamicLanding' in scope` (the type, not the module).

- [ ] **Step 3: Write `MousePassThrough.swift` and `IslandPanel.swift`**

```swift
// DynamicLanding — MousePassThrough.swift
import CoreGraphics

/// The host panel is far larger than the island, so it must not swallow clicks around it: it
/// ignores the mouse unless the pointer is over the island's rect (screen coordinates).
enum MousePassThrough {
    static func shouldIgnoreMouse(pointer: CGPoint, islandRect: CGRect) -> Bool {
        guard !islandRect.isEmpty else { return true }
        return !islandRect.contains(pointer)
    }
}
```

```swift
// DynamicLanding — IslandPanel.swift
import AppKit

/// A non-activating, borderless panel above the menu bar that joins every Space and never
/// takes keyboard focus.
final class IslandPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
```

- [ ] **Step 4: Write `IslandPanelController.swift`**

```swift
// DynamicLanding — IslandPanelController.swift
import AppKit
import SwiftUI

/// Owns the panel for one screen: sizes it to the top-centre half of the screen, hosts the
/// island view top-aligned inside it, and lets clicks through everywhere but the island.
@MainActor
final class IslandPanelController {
    private let model: IslandModel
    private var panel: IslandPanel?
    private var mouseMonitors: [Any] = []
    private(set) var screen: NSScreen?

    init(model: IslandModel) {
        self.model = model
    }

    func present(on screen: NSScreen) {
        self.screen = screen
        if panel == nil {
            let frame = screen.frame
            let size = NSSize(width: frame.width / 2, height: frame.height / 2)
            let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height)
            let panel = IslandPanel(contentRect: NSRect(origin: origin, size: size))
            let hosting = NSHostingView(rootView: IslandView(model: model))
            hosting.frame = NSRect(origin: .zero, size: size)
            panel.contentView = hosting
            self.panel = panel
            installMouseMonitors()
        }
        panel?.orderFrontRegardless()
    }

    func dismiss() {
        panel?.orderOut(nil)
    }

    /// Called whenever the layout changes: pass-through follows the pointer and the island.
    func refreshMousePassThrough() {
        guard let panel else { return }
        let pointer = NSEvent.mouseLocation
        let inside = !MousePassThrough.shouldIgnoreMouse(pointer: pointer, islandRect: model.layout.rect)
        panel.ignoresMouseEvents = !inside
        model.isHovering = inside
    }

    private func installMouseMonitors() {
        let handler: (NSEvent) -> Void = { [weak self] _ in
            Task { @MainActor in self?.refreshMousePassThrough() }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: handler) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { event in handler(event); return event }) {
            mouseMonitors.append(local)
        }
    }

    deinit {
        for monitor in mouseMonitors { NSEvent.removeMonitor(monitor) }
    }
}
```

(`deinit` touching main-actor state: `mouseMonitors` is a plain stored property; if the compiler objects under strict concurrency, make `deinit` call a `nonisolated` helper that takes the array, or remove monitors in `dismiss()` and re-add in `present` — say which in the report.)

- [ ] **Step 5: Write `DynamicLanding.swift`**

```swift
// DynamicLanding — DynamicLanding.swift
import AppKit
import SwiftUI

/// A Dynamic Island for one screen. `show` morphs the island into the new state in place;
/// `hide` animates it away. Both return when the animation has run.
@MainActor @Observable
public final class DynamicLanding {
    public let model: IslandModel
    private let controller: IslandPanelController?
    private var screen: NSScreen?
    private var hideTask: Task<Void, Never>?
    private var generation = 0

    public var state: IslandState { model.state }
    public var isVisible: Bool { model.state != .hidden }
    public var configuration: IslandConfiguration {
        get { model.configuration }
        set { model.configuration = newValue }
    }
    public var onTap: (() -> Void)? {
        get { model.onTap }
        set { model.onTap = newValue }
    }

    /// `screen` nil means `NSScreen.main` at each show. `presentsPanel: false` is the headless
    /// mode for tests and previews: state and content change, no window appears.
    public init(configuration: IslandConfiguration = IslandConfiguration(), screen: NSScreen? = nil, presentsPanel: Bool = true) {
        let target = screen ?? NSScreen.main
        let metrics = target.map { ScreenMetrics(screen: $0) }
            ?? ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), notchSize: nil, menuBarHeight: 24)
        self.model = IslandModel(configuration: configuration, metrics: metrics)
        self.screen = screen
        self.controller = presentsPanel ? IslandPanelController(model: model) : nil
    }

    /// Headless, with explicit metrics (tests).
    init(configuration: IslandConfiguration, metrics: ScreenMetrics, presentsPanel: Bool) {
        self.model = IslandModel(configuration: configuration, metrics: metrics)
        self.controller = presentsPanel ? IslandPanelController(model: model) : nil
    }

    public func show<L: View, T: View>(@ViewBuilder compactLeading: () -> L, @ViewBuilder trailing: () -> T) async {
        model.setCompact(leading: AnyView(compactLeading()), trailing: AnyView(trailing()))
        await transition(to: .compact)
    }

    public func show<C: View>(@ViewBuilder expanded: () -> C) async {
        model.setExpanded(AnyView(expanded()))
        await transition(to: .expanded)
    }

    public func hide() async {
        guard model.state != .hidden else { return }
        generation += 1
        let mine = generation
        hideTask?.cancel()
        let task = Task { @MainActor in
            // `.keepVisible`: wait (up to 10 s) while the pointer is over the island.
            if model.configuration.hoverBehavior.contains(.keepVisible) {
                var waited = 0
                while model.isHovering, waited < 100, generation == mine {
                    try? await Task.sleep(for: .milliseconds(100)); waited += 1
                }
                guard generation == mine else { return }
            }
            withAnimation(model.configuration.animation) { model.setState(.hidden) }
            controller?.refreshMousePassThrough()
            try? await Task.sleep(for: animationDuration)
            // A show that started meanwhile owns the island now; leave its panel alone.
            if generation == mine, model.state == .hidden { controller?.dismiss() }
        }
        hideTask = task
        await task.value
    }

    private func transition(to state: IslandState) async {
        generation += 1
        hideTask?.cancel()
        hideTask = nil
        if let controller {
            let target = screen ?? NSScreen.main
            if let target {
                model.metrics = ScreenMetrics(screen: target)
                controller.present(on: target)
            }
        }
        withAnimation(model.configuration.animation) { model.setState(state) }
        controller?.refreshMousePassThrough()
        try? await Task.sleep(for: animationDuration)
    }

    private var animationDuration: Duration { model.configuration.animationDuration }
}
```

`animationDuration` comes from the configuration (Task 1), so the tests run in milliseconds.

- [ ] **Step 6: Run; all tests pass; `swift build` clean**

Run: `swift build 2>&1 | grep -E "error:|warning:" | head; swift test 2>&1 | grep -E "error:|Test run|failed" | tail -3`. Expected: `Test run with 23 tests passed`. Common fixes: `@Observable` with a `public let model` is fine; `withAnimation` on a model mutation animates the view's `.animation(value:)`-observed layout; if `aShowDuringAHideCancelsTheHide` flakes, the `generation` check is what must make it deterministic — fix the logic, not the test.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "DynamicLanding: show, morph and hide an island on a non-activating panel that lets clicks through around it"
```

---

### Task 5: Demo, CI, first release

**Files:** `Sources/DynamicLandingDemo/main.swift`, `README.md` (final), tag `0.1.0`

- [ ] **Step 1: Write the demo**

```swift
// DynamicLanding — DynamicLandingDemo/main.swift
import AppKit
import DynamicLanding
import SwiftUI

@MainActor
final class DemoApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var island = DynamicLanding()
    private var seconds = 0
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "DynamicLanding")
        let menu = NSMenu()
        menu.addItem(withTitle: "Compact (waveform · timer)", action: #selector(compact), keyEquivalent: "1")
        menu.addItem(withTitle: "Expanded (card)", action: #selector(expanded), keyEquivalent: "2")
        menu.addItem(withTitle: "Hide", action: #selector(hide), keyEquivalent: "0")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Style: automatic", action: #selector(styleAuto), keyEquivalent: "")
        menu.addItem(withTitle: "Style: notch", action: #selector(styleNotch), keyEquivalent: "")
        menu.addItem(withTitle: "Style: pill", action: #selector(stylePill), keyEquivalent: "")
        menu.addItem(withTitle: "Toggle shadow", action: #selector(toggleShadow), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
        island.onTap = { [weak self] in Task { await self?.island.hide() } }
    }

    @objc func compact() {
        seconds = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.seconds += 1; self?.showCompact() }
        }
        showCompact()
    }

    private func showCompact() {
        let s = seconds
        Task {
            await island.show(compactLeading: { Image(systemName: "waveform").font(.system(size: 14, weight: .semibold)) },
                              trailing: { Text(String(format: "%d:%02d", s / 60, s % 60)).font(.system(size: 12, weight: .medium).monospacedDigit()) })
        }
    }

    @objc func expanded() {
        timer?.invalidate()
        Task {
            await island.show(expanded: {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.circle.fill").font(.system(size: 28))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Listening…").font(.headline)
                        Text("Press the shortcut to stop · Email").font(.caption).opacity(0.7)
                    }
                }
            })
        }
    }

    @objc func hide() { timer?.invalidate(); Task { await island.hide() } }
    @objc func styleAuto() { island.configuration.style = .automatic }
    @objc func styleNotch() { island.configuration.style = .notch(topCornerRadius: 15, bottomCornerRadius: 20) }
    @objc func stylePill() { island.configuration.style = .pill(cornerRadius: 16) }
    @objc func toggleShadow() {
        island.configuration.shadow = island.configuration.shadow == .none ? .soft(radius: 10, opacity: 0.4) : .none
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = DemoApp()
app.delegate = delegate
app.run()
```

- [ ] **Step 2: Build everything, run the tests, commit, push, tag**

```bash
swift build 2>&1 | grep -E "error:|warning:" ; swift test 2>&1 | grep -E "Test run|failed" | tail -2
git add -A && git commit -m "Demo app: every state and style from a menu-bar icon" && git push
git tag -a 0.1.0 -m "DynamicLanding 0.1.0" && git push origin 0.1.0
gh run list --limit 1
```

Expected: CI green on the tag. If `swift test` on `macos-latest` lacks a toolchain with Swift Testing, pin the runner's Xcode in `ci.yml` with `sudo xcode-select -s /Applications/Xcode_26*.app` as JustScribe's CI does.

---

### Task 6: JustScribe switches to DynamicLanding

**Files (app repo, branch `dynamic-landing`):**
- Modify: `app/justscribe.xcodeproj/project.pbxproj` (package reference swap), `app/justscribe.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (regenerated), `app/justscribe/Managers/OverlayManager.swift`, `app/justscribe/AppDelegate.swift` (compact listening)
- Delete: `app/justscribe/Vendor/DynamicNotchKit/` (whole directory)

**Interfaces:**
- Consumes: the published package `0.1.0` (`DynamicLanding`, `IslandConfiguration`, `IslandStyle`).
- Produces: `OverlayManager` with the same public surface plus `recordingSeconds: Int` and a compact listening state when `listeningHint == nil`.

- [ ] **Step 1: Swap the package reference in `project.pbxproj`**

Edit the three DynamicNotchKit entries in place (keep their object IDs so nothing else moves):

```
AA0001032F25000000000003 /* XCRemoteSwiftPackageReference "dynamic-landing" */ = {
    isa = XCRemoteSwiftPackageReference;
    repositoryURL = "https://github.com/bring-shrubbery/dynamic-landing";
    requirement = {
        kind = upToNextMajorVersion;
        minimumVersion = 0.1.0;
    };
};
AA0002032F25000000000003 /* DynamicLanding */ = {
    isa = XCSwiftPackageProductDependency;
    package = AA0001032F25000000000003 /* XCRemoteSwiftPackageReference "dynamic-landing" */;
    productName = DynamicLanding;
};
```

and every remaining `/* DynamicNotchKit */` or `"DynamicNotchKit"` comment in the file (the `PBXBuildFile` at the top, the Frameworks list, `packageProductDependencies`, `packageReferences`) becomes `DynamicLanding` / `"dynamic-landing"`. Use `sed -i '' 's#https://github.com/MrKai77/DynamicNotchKit#https://github.com/bring-shrubbery/dynamic-landing#; s/minimumVersion = 1.0.0;/minimumVersion = 0.1.0;/; s/XCRemoteSwiftPackageReference "DynamicNotchKit"/XCRemoteSwiftPackageReference "dynamic-landing"/g; s/DynamicNotchKit/DynamicLanding/g'` — but **only on the lines that mention DynamicNotchKit**; check with `git diff --stat` that only those lines changed and that `minimumVersion = 1.0.0` did not also belong to another package (grep before editing). Then:

```bash
rm -rf app/justscribe/Vendor/DynamicNotchKit && rmdir app/justscribe/Vendor 2>/dev/null
xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -resolvePackageDependencies 2>&1 | tail -3
grep -A4 '"dynamic-landing"' app/justscribe.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
```

Expected: `Package.resolved` gains a `dynamic-landing` entry at `0.1.0` and loses `dynamicnotchkit`.

- [ ] **Step 2: Rewrite `OverlayManager`'s presentation on `DynamicLanding`**

Keep `OverlayExpandedView`, `OverlayStyle`, `OverlayState`, `titleText`, `descriptionText`, `listeningHint`, `onTap`, `isVisible`, `state`, and the five `show*`/`hide` methods' signatures. Replace the `notch`/`shownStyle`/`hideGeneration` machinery with:

```swift
    import DynamicLanding   // at the top of the file

    private var island: DynamicLanding?
    private var islandStyle: OverlayStyle?
    /// Seconds since the recording started, shown in the compact island.
    private(set) var recordingSeconds = 0
    private var recordingTimer: Task<Void, Never>?

    private func currentIsland() -> DynamicLanding {
        if let island, islandStyle == currentStyle { return island }
        Task { [old = island] in await old?.hide() }
        var config = IslandConfiguration()
        config.style = currentStyle == .notch ? .automatic : .pill(cornerRadius: 16)
        config.shadow = .none
        let created = DynamicLanding(configuration: config)
        created.onTap = { [weak self] in self?.onTap?() }
        island = created
        islandStyle = currentStyle
        return created
    }

    /// The expanded card, or the compact waveform-and-timer while listening without a hint.
    private func present() {
        let island = currentIsland()
        isVisible = true
        if case .listening = state, listeningHint == nil {
            let seconds = recordingSeconds
            Task {
                await island.show(
                    compactLeading: { Image(systemName: "waveform").font(.system(size: 14, weight: .semibold)) },
                    trailing: { Text(String(format: "%d:%02d", seconds / 60, seconds % 60)).font(.system(size: 12, weight: .medium).monospacedDigit()) })
            }
        } else {
            let isNotch = currentStyle == .notch
            Task { await island.show(expanded: { OverlayExpandedView(manager: OverlayManager.shared, isNotchStyle: isNotch) }) }
        }
    }
```

`show(style:)` sets `currentStyle` if given and calls `present()`. `showListening()` keeps reading the style from UserDefaults, sets `state = .listening`, starts `recordingTimer` (a `Task` that every second sets `recordingSeconds = Int(AudioCaptureService.shared.recordingDuration)` and calls `present()` while `state == .listening`), then `present()`. `showProcessing/showCompleted/showError` set state, stop the timer, call `present()` and keep their auto-hide tasks. `hide()` cancels the auto-hide and the timer, sets `isVisible = false`, `onTap = nil`, and `Task { await island?.hide() }`, then resets `state = .idle` and `listeningHint = nil` **after** the hide returns (the `DynamicLanding.hide()` await is the hide animation). Remove the `shownStyle`/`hideGeneration` fields and the `OverlayExpandedView`'s own `.onTapGesture`/`contentShape` (the island handles taps; keep the X button calling `onTap ?? hide`).

- [ ] **Step 3: Build, run the suite, commit**

```bash
xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests 2>&1 | grep -E "error:|warning: .*(Overlay|AppDelegate)|\*\* (BUILD|TEST)" | sort -u | tail -5
git add -A app/justscribe app/justscribe.xcodeproj/project.pbxproj app/justscribe.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
git commit -m "The indicator is our own DynamicLanding island: it grows down from the top edge on every screen, shows a compact waveform and timer while you speak, and the vendored DynamicNotchKit is gone"
```

Expected: `** TEST SUCCEEDED **`, no new warnings. If `xcodebuild` cannot resolve the package (network, tag not yet visible), wait a minute and retry; do not point at a local path.

---

### Task 7: Docs and the maintainer's hand checks

**Files:** `CLAUDE.md`, `README.md` (app), `web/src/pages/index.astro` (no change needed unless the indicator is described), the package `README.md` (already final)

- [ ] **Step 1: `CLAUDE.md`** — in "Conventions and gotchas", replace any DynamicNotchKit mention with:

```markdown
- The recording indicator is `DynamicLanding` (github.com/bring-shrubbery/dynamic-landing, our own
  package): `OverlayManager` adapts the app's overlay states to one island per style — compact
  (waveform + timer) while listening in hold mode, expanded otherwise. Its geometry is pure and
  tested in the package; if the island ever looks wrong on a screen, the fix is a geometry test
  there, not a SwiftUI tweak here. The package is a normal SPM dependency in `project.pbxproj`.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md && git commit -m "docs: the indicator is DynamicLanding"
```

- [ ] **Step 3: Hand checks (maintainer)**

1. Built-in notched display, notch style: hold-mode dictation shows the compact island (waveform left of the notch, timer right) growing out of the notch; release → it morphs to the expanded "Processing…" card downward from the notch with the top edge fixed; "Done" → hides back into the notch. No shadow, no bounce.
2. External notchless display as the main screen (focus there): the same session shows a pill hanging from the top edge, centred; the expand grows **down only**; the compact pill is a single rounded tab with the two slots.
3. Bubble style: pill look on both screens.
4. Click next to the island (on the menu bar / desktop): the click reaches what is underneath; click on the island in press mode: stops the recording.
5. Two dictations in quick succession (within 2 s): one island, morphing; never two.
6. Press mode: the expanded hint card ("Press the shortcut to stop · Email") throughout.
7. `swift run DynamicLandingDemo` in `../dynamic-landing`: every menu item behaves; styles switch live.
