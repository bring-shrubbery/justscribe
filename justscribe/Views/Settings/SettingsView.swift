//
//  SettingsView.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var settings: AppSettings?
    @State private var showingModelDownloadModal = false

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

                        ShortcutSettingsSection(settings: settings)

                        Divider()

                        IndicatorSettingsSection(settings: settings)

                        Divider()

                        AppearanceSettingsSection(settings: settings)

                        Divider()

                        BehaviorSettingsSection(settings: settings)

                        Divider()

                        LinksSettingsSection()
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 32)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            settings = AppSettings.getOrCreate(in: modelContext)
        }
        .sheet(isPresented: $showingModelDownloadModal) {
            ModelDownloadModal()
                .frame(minWidth: 500, minHeight: 400)
        }
    }

    private var headerView: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)

            Text("JustScribe")
                .font(.title)
                .fontWeight(.semibold)

            Text("Voice transcription at your fingertips")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 32)
    }
}

// MARK: - Section Container

struct SettingsSectionContainer<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            content
        }
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
        .modelContainer(for: [AppSettings.self, TranscriptionModel.self], inMemory: true)
        .frame(width: 550, height: 800)
}
