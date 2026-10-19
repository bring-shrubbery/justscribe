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

/// What something outside the Settings window asked it to show next ("More Models…" in the
/// Transcripts window opens Settings on the download sheet); the window takes the request when
/// it appears or when it is made, and clears it.
@Observable
final class SettingsRequests {
    static let shared = SettingsRequests()
    var showModelDownload = false
}

/// The panes of the Settings window, in sidebar order. Each groups the sections that belong to
/// one task, so a setting is two clicks away instead of somewhere down a long scroll.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, dictation, microphone, speechModel, cleanUp, modes, vocabulary, historyAndTranscripts, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .dictation: return "Dictation"
        case .microphone: return "Microphone"
        case .speechModel: return "Speech Model"
        case .cleanUp: return "Clean-up"
        case .modes: return "Modes"
        case .vocabulary: return "Vocabulary"
        case .historyAndTranscripts: return "History & Transcripts"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape.fill"
        case .dictation: return "keyboard.fill"
        case .microphone: return "mic.fill"
        case .speechModel: return "waveform"
        case .cleanUp: return "text.badge.checkmark"
        case .modes: return "square.grid.2x2.fill"
        case .vocabulary: return "character.book.closed.fill"
        case .historyAndTranscripts: return "clock.fill"
        case .about: return "info.circle.fill"
        }
    }

    /// The tile colour behind the sidebar icon, in the manner of System Settings.
    var tint: Color {
        switch self {
        case .general: return .gray
        case .dictation: return .blue
        case .microphone: return .red
        case .speechModel: return .purple
        case .cleanUp: return .indigo
        case .modes: return .orange
        case .vocabulary: return .green
        case .historyAndTranscripts: return .brown
        case .about: return .blue
        }
    }

    /// Where the gaps in the sidebar fall: before the first pane of each group.
    var startsGroup: Bool {
        switch self {
        case .general, .cleanUp, .historyAndTranscripts: return true
        default: return false
        }
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var settings: AppSettings?
    @State private var showingModelDownloadModal = false
    @State private var showingOnboarding = false
    @AppStorage("settingsSelectedPane") private var selectedPaneID = SettingsPane.general.rawValue

    private var downloadService: ModelDownloadService { ModelDownloadService.shared }

    private var selectedPane: Binding<SettingsPane?> {
        Binding(
            get: { SettingsPane(rawValue: selectedPaneID) ?? .general },
            set: { if let pane = $0 { selectedPaneID = pane.rawValue } }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: selectedPane) {
                ForEach(SettingsPane.allCases) { pane in
                    SidebarLabel(pane: pane)
                        .tag(pane)
                        .padding(.top, pane.startsGroup && pane != .general ? 10 : 0)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 240)
        } detail: {
            if let settings {
                let pane = selectedPane.wrappedValue ?? .general
                Form {
                    paneContent(pane, settings: settings)
                }
                .formStyle(.grouped)
                .navigationTitle(pane.title)
                .id(pane)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            settings = AppSettings.getOrCreate(in: modelContext)
            checkForOnboarding()
            takeRequests()
        }
        .onChange(of: SettingsRequests.shared.showModelDownload) { takeRequests() }
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

    @ViewBuilder
    private func paneContent(_ pane: SettingsPane, settings: AppSettings) -> some View {
        switch pane {
        case .general:
            PermissionsSettingsSection()
            StartupSettingsSection(settings: settings)
            AppearanceSettingsSection(settings: settings)
            UpdateSettingsSection()
        case .dictation:
            ShortcutSettingsSection(settings: settings)
            DictationBehaviorSettingsSection(settings: settings)
            IndicatorSettingsSection(settings: settings)
        case .microphone:
            MicrophoneSettingsSection(settings: settings)
        case .speechModel:
            ModelSettingsSection(settings: settings, showingModelDownloadModal: $showingModelDownloadModal)
            RAMEstimateSection(settings: settings)
        case .cleanUp:
            CleanUpSettingsSection(settings: settings)
            if settings.grammarCorrectionEnabled {
                RAMEstimateSection(settings: settings)
            }
        case .modes:
            ModesSettingsSection()
        case .vocabulary:
            VocabularySettingsSection()
        case .historyAndTranscripts:
            HistorySettingsSection(settings: settings)
            TranscriptsSettingsSection()
        case .about:
            SupportSettingsSection()
            LinksSettingsSection()
            DiagnosticsSettingsSection()
            #if DEBUG
            SettingsSectionContainer(title: "Developer") {
                Button("Reset Onboarding") {
                    showingOnboarding = true
                }
                .buttonStyle(.pill)
            }
            #endif
        }
    }

    private func takeRequests() {
        let requests = SettingsRequests.shared
        guard requests.showModelDownload else { return }
        requests.showModelDownload = false
        selectedPaneID = SettingsPane.speechModel.rawValue
        showingModelDownloadModal = true
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
}

/// A sidebar entry: a coloured tile with the pane's symbol, then its name.
private struct SidebarLabel: View {
    let pane: SettingsPane

    var body: some View {
        Label {
            Text(pane.title)
        } icon: {
            Image(systemName: pane.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(pane.tint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

/// How much memory the chosen speech and clean-up models take together; shown under each of
/// the two panes that decide it.
private struct RAMEstimateSection: View {
    @Bindable var settings: AppSettings

    private var totalMB: Int {
        RAMEstimate.totalMB(
            transcriptionModelID: settings.selectedModelID,
            grammarEnabled: settings.grammarCorrectionEnabled,
            grammarModelID: settings.selectedGrammarModelID
        )
    }

    var body: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "memorychip")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Estimated RAM usage")
                        .font(.body)
                    Text("Speech model and clean-up model together, while loaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(RAMEstimate.format(totalMB: totalMB))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Section Container

/// One group of a pane: a `Section` of the grouped form, titled, with an optional control at
/// the right of the title. Each direct child of `content` is a row of the group's card.
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
        Section {
            content()
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer()
                accessory()
            }
        }
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

/// A row with a symbol, a title over a caption, and a switch at the right.
struct ToggleSettingsRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.pill)
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: AppSettings.self, inMemory: true)
        .frame(width: 760, height: 560)
}
