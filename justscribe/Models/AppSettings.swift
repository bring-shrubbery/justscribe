//
//  AppSettings.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import Foundation
import SwiftData

enum IndicatorStyle: String, Codable, CaseIterable {
    case bubble = "bubble"
    case notch = "notch"

    var displayName: String {
        switch self {
        case .bubble: return "Floating Bubble"
        case .notch: return "Notch (Dynamic Island)"
        }
    }
}

enum AppearanceMode: String, Codable, CaseIterable {
    case light = "light"
    case dark = "dark"
    case system = "system"

    var displayName: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }
}

@Model
final class AppSettings {
    // UserDefaults keys for cross-component access
    static let selectedModelIDKey = "selectedModelID"
    static let escapeToCancelKey = "escapeToCancel"
    static let copyToClipboardKey = "copyToClipboard"

    // Model selection (synced to UserDefaults for AppDelegate access)
    var selectedModelID: String = "" {
        didSet {
            UserDefaults.standard.set(selectedModelID, forKey: Self.selectedModelIDKey)
        }
    }

    // Microphone priority (ordered array of device UIDs)
    var microphonePriority: [String] = []

    // Shortcut (stored as raw key + modifiers)
    var shortcutKeyCode: UInt16 = 0
    var shortcutModifiers: UInt = 0

    // Indicator style
    @Attribute var indicatorStyleRaw: String = IndicatorStyle.bubble.rawValue
    var indicatorStyle: IndicatorStyle {
        get { IndicatorStyle(rawValue: indicatorStyleRaw) ?? .bubble }
        set { indicatorStyleRaw = newValue.rawValue }
    }

    // Appearance
    @Attribute var appearanceModeRaw: String = AppearanceMode.system.rawValue
    var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceModeRaw) ?? .system }
        set { appearanceModeRaw = newValue.rawValue }
    }

    // UI Language
    var selectedLanguage: String = "en"

    // Behavior toggles
    var launchAtLogin: Bool = false
    var showInDock: Bool = true
    var showInStatusBar: Bool = true
    var escapeToCancel: Bool = true {
        didSet {
            UserDefaults.standard.set(escapeToCancel, forKey: Self.escapeToCancelKey)
        }
    }
    var copyToClipboard: Bool = true {
        didSet {
            UserDefaults.standard.set(copyToClipboard, forKey: Self.copyToClipboardKey)
        }
    }

    // Timestamps
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}

    static func getOrCreate(in context: ModelContext) -> AppSettings {
        let descriptor = FetchDescriptor<AppSettings>()
        let existing = try? context.fetch(descriptor)

        if let settings = existing?.first {
            // Sync to UserDefaults (didSet may not fire on SwiftData load)
            settings.syncToUserDefaults()
            return settings
        }

        let settings = AppSettings()
        context.insert(settings)
        return settings
    }

    func syncToUserDefaults() {
        UserDefaults.standard.set(selectedModelID, forKey: Self.selectedModelIDKey)
        UserDefaults.standard.set(escapeToCancel, forKey: Self.escapeToCancelKey)
        UserDefaults.standard.set(copyToClipboard, forKey: Self.copyToClipboardKey)
    }
}
