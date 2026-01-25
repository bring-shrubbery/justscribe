//
//  AppearanceSettingsSection.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import SwiftUI

struct AppearanceSettingsSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsSectionContainer(title: "Appearance") {
            VStack(spacing: 16) {
                // Appearance Mode
                SettingsRow(title: "Theme", subtitle: "Choose your preferred color scheme") {
                    Picker("Theme", selection: Binding(
                        get: { settings.appearanceMode },
                        set: { newValue in
                            settings.appearanceMode = newValue
                            applyAppearance(newValue)
                        }
                    )) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }

                // Language
                SettingsRow(title: "Language", subtitle: "UI display language") {
                    Picker("Language", selection: $settings.selectedLanguage) {
                        ForEach(Constants.SupportedLanguages.all, id: \.code) { language in
                            Text(language.name).tag(language.code)
                        }
                    }
                    .frame(width: 150)
                }
            }
        }
    }

    private func applyAppearance(_ mode: AppearanceMode) {
        switch mode {
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case .system:
            NSApp.appearance = nil
        }
    }
}
