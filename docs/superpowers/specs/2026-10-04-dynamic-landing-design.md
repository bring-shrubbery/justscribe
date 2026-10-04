# DynamicLanding — design

A small Swift package that draws a Dynamic Island on macOS: a floating panel pinned to the
top edge of a screen that is flush with the notch where there is one and a rounded pill
hanging from the top edge where there is not. Three states — hidden, compact (a leading and a
trailing slot, as iOS Live Activities show around the island), expanded (rich content) — and
every animation anchored at the top edge, growing downward and widening symmetrically about
the screen's centre. JustScribe replaces its vendored DynamicNotchKit with it.

```
hidden      ▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁        (the notch itself, or nothing on a notchless screen)
compact     ▁▁▁▁▁▁▁[≋] ██████ [0:12]▁▁▁▁  (slots flank the notch; one pill on a notchless screen)
expanded    ▁▁▁▁▁▁▁╭──────────────╮▁▁▁▁
                   │ Listening…   │
                   │ Email        │
                   ╰──────────────╯
```

## Decisions

| Question | Decision |
|---|---|
| Why not keep patching DynamicNotchKit | Its layout is built around the notch; on a notchless screen the island inflates from its own centre, and every fix is a fork anyway. The geometry we need is ~200 lines of maths we can test. |
| Where it lives | A sibling repository `../dynamic-landing`, published as `github.com/bring-shrubbery/dynamic-landing`, MIT. Package `DynamicLanding`, library product `DynamicLanding`, demo executable `DynamicLandingDemo`. |
| Platforms, tooling | macOS 14+; `swift-tools-version: 5.10`; Swift 5 language mode with strict concurrency `complete` (the package is `@MainActor` where it touches AppKit and `Sendable` elsewhere); no dependencies. |
| How JustScribe consumes it | A Swift package dependency added to `project.pbxproj` by a script and proven by `xcodebuild` (the one case the "never hand-edit" rule bends); `from: "0.1.0"`. The vendored copy and the old DynamicNotchKit reference are removed in the same change. |
| First release | Tag `0.1.0` once the package tests pass and JustScribe builds against it. |

## Behaviour

### Placement and shape

- One `DynamicLanding` instance presents on one `NSScreen` (default: `NSScreen.main`, the
  screen with keyboard focus). The island's **top edge is the screen's top edge** and its
  **horizontal centre is the screen's centre**, in every state and at every frame of every
  animation. These two invariants are tested.
- **Notched screen** (`safeAreaInsets.top > 0` with auxiliary top areas): the hidden state is
  the notch rectangle itself; compact and expanded islands are at least the notch's width and
  height, so the black shape always covers the notch. Corner radii: top corners follow the
  screen's own notch radius (configurable), bottom corners larger.
- **Notchless screen**: the hidden state is a zero-height line at the top edge centred on the
  screen; compact is a pill `compactHeight` (default 32 pt) tall; expanded is a pill as tall as
  its content. The pill hangs from the top edge (no gap).
- `IslandStyle`: `.automatic` (as above), `.notch(topCornerRadius:bottomCornerRadius:)` (force
  the notch look even without a notch), `.pill(cornerRadius:)` (force the pill look, hanging
  from the top edge even on a notched screen).

### States and content

- `hidden`, `compact(leading:trailing:)`, `expanded(content)`. Content is SwiftUI, passed with
  `@ViewBuilder`, type-erased inside the package.
- **Compact**: the leading view sits left of the notch (or the pill's left half), the trailing
  view right of it; each slot is as wide as its content plus padding; the island's height is
  the notch height (or `compactHeight`). Content is vertically centred in the slot.
- **Expanded**: the content is laid out below the notch area (a top inset equal to the notch
  height on notched screens, `expandedTopInset` otherwise) with `contentPadding` around it; the
  island is as wide as the content plus padding, never narrower than the notch, and as tall as
  the inset plus the content.
- Showing while already showing **morphs**: compact → expanded grows the shape and fades the
  new content in; expanded → compact shrinks it. Content of the same state replaces in place
  with a fade. There is never a second panel.
- `hide()` animates to hidden and then orders the panel out; re-showing during the hide
  animation cancels the hide and morphs forward.

### Animation

- Driven by SwiftUI: the shape's frame follows the measured content size through the
  configured animation (`.smooth(duration: 0.35)` by default); content transitions are
  `.opacity`. No spring overshoot unless the caller passes a springy animation.
- Top anchoring is structural, not a transition parameter: every container in the view tree
  is `alignment: .top`, the host panel is pinned to the screen's top edge, and the shape is
  positioned by the geometry's rect (origin at the top edge). A notchless screen and a notched
  one use the same code path with different `ScreenMetrics`.

### Interaction

- `onTap: (() -> Void)?` fires for a click anywhere on the island shape (not the transparent
  panel around it).
- `hoverBehavior`: `[]` by default; `.keepVisible` delays a pending `hide()` while the pointer
  is over the island; `.highlight` raises the material slightly on hover.
- The panel is non-activating, joins all Spaces, stays above the menu bar and full-screen apps'
  menu bars (`.mainMenu + 1` level, `.fullScreenAuxiliary`), ignores mouse events outside the
  shape, and never takes keyboard focus.

### Configuration

```swift
public struct IslandConfiguration: Sendable {
    public var style: IslandStyle = .automatic
    public var animation: Animation = .smooth(duration: 0.35)
    public var shadow: IslandShadow = .none          // .none | .soft(radius: CGFloat, opacity: CGFloat)
    public var background: IslandBackground = .black // .black | .color(Color) | .material(NSVisualEffectView.Material)
    public var foreground: Color = .white
    public var contentPadding: EdgeInsets = EdgeInsets(top: 10, leading: 16, bottom: 12, trailing: 16)
    public var compactHeight: CGFloat = 32           // notchless screens
    public var expandedTopInset: CGFloat = 8         // notchless screens
    public var notchCornerRadii: (top: CGFloat, bottom: CGFloat) = (top: 15, bottom: 20)
    public var pillCornerRadius: CGFloat = 16
    public var hoverBehavior: IslandHoverBehavior = []
}
```

## Components (package)

```
Sources/DynamicLanding/
  DynamicLanding.swift          @MainActor @Observable public final class — the API
  IslandState.swift             public enum IslandState { hidden, compact, expanded }
  IslandConfiguration.swift     the struct above, IslandStyle, IslandShadow, IslandBackground, IslandHoverBehavior
  Geometry/ScreenMetrics.swift  nonisolated struct ScreenMetrics { frame, notchSize: CGSize?, menuBarHeight }; init(screen: NSScreen)
  Geometry/IslandGeometry.swift nonisolated enum IslandGeometry — pure layout maths (tested)
  Panel/IslandPanel.swift       NSPanel subclass (non-activating, level, collection behaviour, hit testing)
  Panel/IslandPanelController.swift  owns the panel, hosts IslandView, pins the panel to the screen's top edge
  Views/IslandView.swift        the shape + content, laid out from IslandGeometry, top-aligned everywhere
  Views/IslandShape.swift       the notch/pill path with independent top/bottom radii
  Views/SizeReader.swift        measures content size (onGeometryChange)
Sources/DynamicLandingDemo/main.swift   a menu-bar demo: buttons for hidden/compact/expanded, style and screen pickers
Tests/DynamicLandingTests/
  IslandGeometryTests.swift     notched and notchless screens, all states; invariants; radii; slots
  ScreenMetricsTests.swift      metrics from synthetic values
  DynamicLandingStateTests.swift  show/hide/morph sequences on the model (no window)
```

### `IslandGeometry` (the tested core)

```swift
nonisolated struct IslandLayout: Equatable, Sendable {
    var rect: CGRect              // in screen coordinates (AppKit, origin bottom-left)
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat
    var leadingSlot: CGRect?      // compact only, in island-local coordinates (top-left origin)
    var trailingSlot: CGRect?
    var contentRect: CGRect?      // expanded only, island-local
}

nonisolated enum IslandGeometry {
    static func layout(state: IslandState, metrics: ScreenMetrics, style: IslandStyle,
                       configuration: IslandConfiguration, compactSlotSizes: (leading: CGSize, trailing: CGSize),
                       expandedContentSize: CGSize) -> IslandLayout
}
```

Invariants checked by tests for every state, on a notched (notch 200×38) and a notchless
screen, with `.automatic`, `.notch`, `.pill`:
`rect.maxY == metrics.frame.maxY`; `abs(rect.midX - metrics.frame.midX) < 0.5`;
`rect.width >= notchSize.width` on notched screens; hidden on notched = the notch rect, hidden
on notchless has zero height; compact height = notch height / `compactHeight`; expanded height
= inset + content + padding; slots do not overlap the notch; morphing between any two states
keeps the first two invariants at both ends (interpolation is linear in SwiftUI, so holding
at both ends holds throughout).

### `DynamicLanding` (the API)

```swift
@MainActor @Observable
public final class DynamicLanding {
    public private(set) var state: IslandState
    public var configuration: IslandConfiguration
    public var onTap: (() -> Void)?
    public init(configuration: IslandConfiguration = .init(), screen: NSScreen? = nil)
    public func show<L: View, T: View>(compactLeading: () -> L, trailing: () -> T) async
    public func show<C: View>(expanded: () -> C) async
    public func hide() async
    public var isVisible: Bool { state != .hidden }
}
```

`show` returns when the animation has finished (the configured animation's duration). Calls
are serialised on the main actor; a `show` during a `hide` cancels the hide.

## JustScribe adoption

- `OverlayManager` keeps its public surface (`showListening/showProcessing/showCompleted/showError/hide`,
  `state`, `titleText`, `descriptionText`, `listeningHint`, `onTap`, `OverlayStyle`) and
  becomes an adapter over one `DynamicLanding` per style: `.bubble` → `.pill`, `.notch` →
  `.automatic`. `OverlayExpandedView` is the expanded content, unchanged.
- **Listening in hold mode** shows the **compact** state: a `waveform` symbol leading and the
  elapsed time (`0:12`) trailing, updated once a second from `AudioCaptureService.recordingDuration`.
  Press mode (which needs the hint text), processing, completed and error use the expanded card
  as today. The compact → expanded morph replaces today's second panel.
- `app/justscribe/Vendor/DynamicNotchKit/` is deleted; the DynamicNotchKit package reference is
  removed from `project.pbxproj` and `Package.resolved`; `DynamicLanding` is added. CLAUDE.md's
  Indicator notes are updated.

## Error handling

| Situation | Behaviour |
|---|---|
| No screen (headless / tests) | `show` sets state and content without a panel; nothing crashes. |
| The chosen screen disconnects while shown | The island hides; the next `show` picks `NSScreen.main`. |
| Content larger than half the screen | Clamped to half the screen's width/height; content clips. |
| `show` called twice before the first animation ends | The second wins; the panel morphs from wherever it is. |
| `hide` with nothing shown | No-op. |

## Testing

- Package: the geometry invariants above (property-style loops over sizes); `ScreenMetrics`
  from synthetic inputs; state-machine sequences on the model; `swift build` of the demo. CI:
  GitHub Actions on `macos-latest`, `swift build && swift test`.
- JustScribe: existing suite stays green; the adapter has no new unit tests (it is wiring); the
  maintainer's hand checks: notched built-in display and an external notchless display, all
  states, hold and press modes, bubble and notch styles, tap-to-stop, auto-hide, rapid repeat
  dictations (no orphan).

## Out of scope

Windows/Linux, multiple simultaneous islands on one screen, drag to reposition, haptics,
menu-bar-item-anchored popovers, and theming beyond colour/material.
