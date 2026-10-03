//
//  AppSettings.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
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

    var iconName: String {
        switch self {
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .system: return "circle.lefthalf.filled"
        }
    }
}

@Model
final class AppSettings {
    // UserDefaults keys for cross-component access
    static let selectedModelIDKey = "selectedModelID"
    static let copyToClipboardKey = "copyToClipboard"
    static let selectedLanguageKey = "selectedLanguage"
    static let microphonePriorityKey = "microphonePriority"
    static let bannedMicrophoneIDsKey = "bannedMicrophoneIDs"
    static let indicatorStyleKey = "indicatorStyle"
    static let showInDockKey = "showInDock"
    static let showInStatusBarKey = "showInStatusBar"
    static let grammarCorrectionEnabledKey = "grammarCorrectionEnabled"
    static let selectedGrammarModelIDKey = "selectedGrammarModelID"
    static let textInsertionModeKey = "textInsertionMode"
    static let historyKeepsTranscriptionsKey = "historyKeepsTranscriptions"
    static let historyKeepsAudioKey = "historyKeepsAudio"

    // Model selection (synced to UserDefaults for AppDelegate access)
    var selectedModelID: String = "" {
        didSet {
            UserDefaults.standard.set(selectedModelID, forKey: Self.selectedModelIDKey)
        }
    }

    // Microphone priority (ordered array of device UIDs)
    var microphonePriority: [String] = [] {
        didSet {
            UserDefaults.standard.set(microphonePriority, forKey: Self.microphonePriorityKey)
        }
    }

    // Microphones the user has explicitly blocked from being selected
    var bannedMicrophoneIDs: [String] = [] {
        didSet {
            UserDefaults.standard.set(bannedMicrophoneIDs, forKey: Self.bannedMicrophoneIDsKey)
        }
    }

    // Shortcut (stored as raw key + modifiers)
    var shortcutKeyCode: UInt16 = 0
    var shortcutModifiers: UInt = 0

    // How dictated text reaches the focused app
    @Attribute var textInsertionModeRaw: String = TextInsertionMode.defaultMode.rawValue
    var textInsertionMode: TextInsertionMode {
        get { TextInsertionMode.stored(textInsertionModeRaw) }
        set {
            textInsertionModeRaw = newValue.rawValue
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.textInsertionModeKey)
        }
    }

    // History (off by default: nothing is kept unless the user asks)
    var historyKeepsTranscriptions: Bool = false {
        didSet {
            UserDefaults.standard.set(historyKeepsTranscriptions, forKey: Self.historyKeepsTranscriptionsKey)
            if !historyKeepsTranscriptions && historyKeepsAudio { historyKeepsAudio = false }
        }
    }
    var historyKeepsAudio: Bool = false {
        didSet {
            UserDefaults.standard.set(historyKeepsAudio, forKey: Self.historyKeepsAudioKey)
        }
    }

    // Indicator style
    @Attribute var indicatorStyleRaw: String = IndicatorStyle.bubble.rawValue
    var indicatorStyle: IndicatorStyle {
        get { IndicatorStyle(rawValue: indicatorStyleRaw) ?? .bubble }
        set {
            indicatorStyleRaw = newValue.rawValue
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.indicatorStyleKey)
        }
    }

    // Appearance
    @Attribute var appearanceModeRaw: String = AppearanceMode.system.rawValue
    var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceModeRaw) ?? .system }
        set { appearanceModeRaw = newValue.rawValue }
    }

    // UI Language (also used for transcription)
    var selectedLanguage: String = "en" {
        didSet {
            UserDefaults.standard.set(selectedLanguage, forKey: Self.selectedLanguageKey)
        }
    }

    // Behavior toggles
    var launchAtLogin: Bool = false
    var showInDock: Bool = true {
        didSet {
            UserDefaults.standard.set(showInDock, forKey: Self.showInDockKey)
        }
    }
    var showInStatusBar: Bool = true {
        didSet {
            UserDefaults.standard.set(showInStatusBar, forKey: Self.showInStatusBarKey)
        }
    }
    var copyToClipboard: Bool = true {
        didSet {
            UserDefaults.standard.set(copyToClipboard, forKey: Self.copyToClipboardKey)
        }
    }
    var grammarCorrectionEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(grammarCorrectionEnabled, forKey: Self.grammarCorrectionEnabledKey)
        }
    }
    var selectedGrammarModelID: String = GrammarCorrectionModel.defaultModelID {
        didSet {
            UserDefaults.standard.set(selectedGrammarModelID, forKey: Self.selectedGrammarModelIDKey)
        }
    }

    // Timestamps
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}

    /// Resolve a stored grammar model selection. A blank or unrecognised value
    /// becomes the default; an explicit, still-valid choice is left alone.
    nonisolated static func normalizedGrammarModelID(_ stored: String) -> String {
        GrammarCorrectionModel.model(forID: stored) != nil
            ? stored
            : GrammarCorrectionModel.defaultModelID
    }

    static func getOrCreate(in context: ModelContext) -> AppSettings {
        let descriptor = FetchDescriptor<AppSettings>()
        let existing = try? context.fetch(descriptor)

        if let settings = existing?.first {
            // Existing rows keep whatever they stored, except a blank or stale
            // selection, which resolves to the current default.
            let normalized = Self.normalizedGrammarModelID(settings.selectedGrammarModelID)
            if normalized != settings.selectedGrammarModelID {
                settings.selectedGrammarModelID = normalized
            }
            // Sync to UserDefaults (didSet may not fire on SwiftData load)
            settings.syncToUserDefaults()
            return settings
        }

        let settings = AppSettings()
        context.insert(settings)
        settings.syncToUserDefaults()
        return settings
    }

    func syncToUserDefaults() {
        UserDefaults.standard.set(selectedModelID, forKey: Self.selectedModelIDKey)
        UserDefaults.standard.set(copyToClipboard, forKey: Self.copyToClipboardKey)
        UserDefaults.standard.set(selectedLanguage, forKey: Self.selectedLanguageKey)
        UserDefaults.standard.set(microphonePriority, forKey: Self.microphonePriorityKey)
        UserDefaults.standard.set(bannedMicrophoneIDs, forKey: Self.bannedMicrophoneIDsKey)
        UserDefaults.standard.set(indicatorStyleRaw, forKey: Self.indicatorStyleKey)
        UserDefaults.standard.set(textInsertionModeRaw, forKey: Self.textInsertionModeKey)
        UserDefaults.standard.set(showInDock, forKey: Self.showInDockKey)
        UserDefaults.standard.set(showInStatusBar, forKey: Self.showInStatusBarKey)
        UserDefaults.standard.set(grammarCorrectionEnabled, forKey: Self.grammarCorrectionEnabledKey)
        UserDefaults.standard.set(selectedGrammarModelID, forKey: Self.selectedGrammarModelIDKey)
        UserDefaults.standard.set(historyKeepsTranscriptions, forKey: Self.historyKeepsTranscriptionsKey)
        UserDefaults.standard.set(historyKeepsAudio, forKey: Self.historyKeepsAudioKey)
    }
}
