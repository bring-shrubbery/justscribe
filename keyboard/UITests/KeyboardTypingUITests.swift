//
//  KeyboardTypingUITests.swift
//  JustScribeKeyboard
//
//  Created by Antoni Silvestrovic on 27/10/2026.
//
//  Copyright (C) 2026 Quassum MB
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

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
    static let keys: [Character: CGPoint] = [
        "h": CGPoint(x: 240.8, y: 664.3),
        "e": CGPoint(x: 102.3, y: 609.7),
        "l": CGPoint(x: 358.8, y: 664.3),
        "o": CGPoint(x: 339.2, y: 609.7),
        "i": CGPoint(x: 299.7, y: 609.7),
        " ": CGPoint(x: 200.2, y: 771.4),
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
