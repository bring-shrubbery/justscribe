import XCTest

/// Types on the JustScribe keyboard with real touches, in the app's debug keyboard lab.
///
/// The simulator must have the JustScribe keyboard enabled and selected
/// (`AppleKeyboards` in its global defaults); see keyboard/README.md.
@MainActor
final class KeyboardTypingUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-keyboardLab", "YES"]
        app.launch()
    }

    /// Records what the keyboard exposes to accessibility, for writing the tests below.
    func testDumpKeyboardHierarchy() throws {
        sleep(2)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        print("APP HIERARCHY\n\(app.debugDescription)")
        print("SPRINGBOARD KEYBOARDS\n\(springboard.keyboards.debugDescription)")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Where the keys of the current layout are, in points on an iPhone 17 Pro (402 × 874).
    /// Measured from a screenshot; update after changing the layout.
    static var keys: [Character: CGPoint] = [
        "h": CGPoint(x: 240.8, y: 657.7),
        "e": CGPoint(x: 100.1, y: 602.2),
        "l": CGPoint(x: 361.4, y: 657.7),
        "o": CGPoint(x: 341.3, y: 602.2),
        "i": CGPoint(x: 301.1, y: 602.2),
        " ": CGPoint(x: 200.0, y: 770.0),
    ]

    private func tap(_ key: Character) {
        let point = Self.keys[key]!
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x, dy: point.y))
            .tap()
    }

    private var fieldText: String {
        let field = app.descendants(matching: .any)["lab-field"]
        let value = (field.value as? String) ?? ""
        return value == "Message" ? "" : value
    }

    /// Each tap must reach the field, and soon: a key that lands only after the next
    /// tap, or a second later, is the iOS 27 gesture lag.
    func testTypingReachesTheField() throws {
        sleep(UInt32(ProcessInfo.processInfo.environment["KEYBOARD_WAIT"] ?? "6") ?? 6)
        var latencies: [String] = []
        var typed = ""
        for key in "hello " {
            let before = fieldText
            let start = Date()
            tap(key)
            while fieldText == before, Date().timeIntervalSince(start) < 3 {
                usleep(20_000)
            }
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            latencies.append("\(key == " " ? "space" : String(key)): \(fieldText == before ? "NOTHING" : "\(ms) ms")")
            typed = fieldText
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "after \(key == " " ? "space" : String(key))"
            shot.lifetime = .keepAlways
            add(shot)
        }
        print("TYPING LATENCIES: \(latencies.joined(separator: ", "))")
        print("TYPED TEXT: [\(typed)]")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertEqual(typed.lowercased(), "hello ")
    }
}
