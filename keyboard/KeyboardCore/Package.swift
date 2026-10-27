// swift-tools-version: 6.2

// The keyboard engine behind the JustScribe keyboard: layouts, keys, callouts,
// gestures and the input view controller. It started from the MIT-licensed
// source of KeyboardKit 9.9.1 (see LICENSE) with its paid-feature placeholders removed.

import PackageDescription

let package = Package(
    name: "KeyboardCore",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(name: "KeyboardCore", targets: ["KeyboardCore"])
    ],
    targets: [
        .target(
            name: "KeyboardCore",
            resources: [.process("Resources")],
            // Asset symbols (Color(.name)) resolve against the main bundle in optimized
            // builds of a statically linked package, which drew every key invisible.
            // Colors and images name Bundle.keyboardCore explicitly instead.
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
