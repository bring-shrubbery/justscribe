//
//  AppearanceSettingsSection.swift
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

import SwiftUI

struct AppearanceSettingsSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsSectionContainer(title: "Appearance") {
            VStack(spacing: 16) {
                // Appearance Mode
                SettingsRow(title: "Theme", subtitle: "Choose your preferred color scheme") {
                    AppearanceModePicker(selection: Binding(
                        get: { settings.appearanceMode },
                        set: { newValue in
                            settings.appearanceMode = newValue
                            applyAppearance(newValue)
                        }
                    ))
                }

                // Language - commented out until localization is implemented
                // SettingsRow(title: "Language", subtitle: "UI display language") {
                //     Picker("Language", selection: $settings.selectedLanguage) {
                //         ForEach(Constants.SupportedLanguages.all, id: \.code) { language in
                //             Text(language.name).tag(language.code)
                //         }
                //     }
                //     .labelsHidden()
                // }
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

private struct AppearanceModePicker: View {
    @Binding var selection: AppearanceMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppearanceMode.allCases, id: \.self) { mode in
                segment(for: mode)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .separatorColor).opacity(0.35))
        )
    }

    @ViewBuilder
    private func segment(for mode: AppearanceMode) -> some View {
        let isSelected = selection == mode
        Button {
            selection = mode
        } label: {
            Image(systemName: mode.iconName)
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 52, height: 30)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .shadow(color: .black.opacity(0.08), radius: 1, y: 0.5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(mode.displayName)
    }
}
