//
//  SettingsView.swift
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
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var settings: AppSettings?
    @State private var showingModelDownloadModal = false
    @State private var showingOnboarding = false

    private var downloadService: ModelDownloadService { ModelDownloadService.shared }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                headerView

                if let settings = settings {
                    VStack(spacing: 24) {
                        ModelSettingsSection(
                            settings: settings,
                            showingModelDownloadModal: $showingModelDownloadModal
                        )

                        Divider()

                        MicrophoneSettingsSection(settings: settings)

                        Divider()

                        ShortcutSettingsSection()

                        Divider()

                        IndicatorSettingsSection(settings: settings)

                        Divider()

                        GrammarCorrectionSettingsSection(settings: settings)

                        Divider()

                        AppearanceSettingsSection(settings: settings)

                        Divider()

                        BehaviorSettingsSection(settings: settings)

                        Divider()

                        TipJarSettingsSection()

                        Divider()

                        LinksSettingsSection()

                        #if DEBUG
                        Divider()

                        SettingsSectionContainer(title: "Developer") {
                            Button("Reset Onboarding") {
                                showingOnboarding = true
                            }
                            .buttonStyle(.bordered)
                        }
                        #endif
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 32)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            settings = AppSettings.getOrCreate(in: modelContext)
            checkForOnboarding()
        }
        .sheet(isPresented: $showingModelDownloadModal) {
            if let settings = settings {
                ModelDownloadModal(settings: settings)
                    .frame(minWidth: 500, minHeight: 400)
            }
        }
        .sheet(isPresented: $showingOnboarding) {
            if let settings = settings {
                OnboardingView(isPresented: $showingOnboarding, settings: settings)
            }
        }
    }

    private func checkForOnboarding() {
        // Show onboarding if no models are downloaded
        Task {
            await downloadService.refreshDownloadedModels()
            if downloadService.downloadedModels.isEmpty {
                showingOnboarding = true
            }
        }
    }

    private var headerView: some View {
        VStack(spacing: 8) {
            if let appIcon = NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
            }

            Text("JustScribe")
                .font(.title)
                .fontWeight(.semibold)

            Text("Voice transcription at your fingertips")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let settings = settings {
                RAMEstimateLabel(settings: settings)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 32)
    }
}

private struct RAMEstimateLabel: View {
    @Bindable var settings: AppSettings

    private var totalMB: Int {
        RAMEstimate.totalMB(
            transcriptionModelID: settings.selectedModelID,
            grammarEnabled: settings.grammarCorrectionEnabled,
            grammarModelID: settings.selectedGrammarModelID
        )
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "memorychip")
            Text("Estimated RAM usage: \(RAMEstimate.format(totalMB: totalMB))")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Section Container

struct SettingsSectionContainer<Content: View, Accessory: View>: View {
    let title: String
    @ViewBuilder let accessory: () -> Accessory
    @ViewBuilder let content: () -> Content

    init(title: String,
         @ViewBuilder accessory: @escaping () -> Accessory,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                accessory()
            }

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension SettingsSectionContainer where Accessory == EmptyView {
    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, accessory: { EmptyView() }, content: content)
    }
}

// MARK: - Row Styles

struct SettingsRow<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            content
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: AppSettings.self, inMemory: true)
        .frame(width: 480, height: 800)
}
