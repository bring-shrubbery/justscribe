//
//  CleanUpSettingsSection.swift
//  justscribe
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

import AppKit
import SwiftUI

struct CleanUpSettingsSection: View {
    @Bindable var settings: AppSettings
    private var service: GrammarCorrectionService { GrammarCorrectionService.shared }

    var body: some View {
        SettingsSectionContainer(title: "Clean-up") {
            VStack(spacing: 12) {
                ToggleSettingsRow(
                    title: "Clean Up Text",
                    subtitle: "Fix grammar, spelling and punctuation, or follow the instructions of the mode for the app you dictate into",
                    systemImage: "text.badge.checkmark",
                    isOn: Binding(
                        get: { settings.grammarCorrectionEnabled },
                        set: { newValue in
                            settings.grammarCorrectionEnabled = newValue
                            UserDefaults.standard.set(newValue, forKey: AppSettings.grammarCorrectionEnabledKey)
                            if !newValue {
                                service.unloadModel()
                            } else if !settings.selectedGrammarModelID.isEmpty,
                                      service.isReadyToUse(settings.selectedGrammarModelID) {
                                let modelID = settings.selectedGrammarModelID
                                Task { try? await service.loadModel(modelID: modelID) }
                            }
                        }
                    )
                )

                if settings.grammarCorrectionEnabled {
                    ForEach(GrammarCorrectionModel.allModels.filter { !$0.backend.isHosted }) { model in
                        Divider()
                        switch model.backend {
                        case .apple:
                            AppleGrammarModelRow(model: model, settings: settings)
                        case .mlx:
                            MLXGrammarModelRow(model: model, settings: settings)
                        case .hosted:
                            EmptyView()
                        }
                    }
                    Divider()
                    HostedGrammarRow(settings: settings)
                    Divider()
                    ModesList(store: ModeStore.shared)
                }
            }
        }
    }
}

private struct MLXGrammarModelRow: View {
    let model: GrammarCorrectionModel
    @Bindable var settings: AppSettings
    private var service: GrammarCorrectionService { GrammarCorrectionService.shared }

    private var isDownloaded: Bool { service.isReadyToUse(model.id) }
    private var isDownloading: Bool { service.activelyDownloadingModelID == model.id }
    private var isLoadingThisModel: Bool {
        service.isLoadingModel && service.loadedModelID != model.id && !isDownloading
    }
    private var isLoadedAndSelected: Bool {
        service.isModelLoaded && service.loadedModelID == model.id
    }

    private var subtitleText: String {
        [model.provider, model.approximateSize, model.approximateRAM.map { "RAM \($0)" }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(.body)
                Text(subtitleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if isDownloading {
                    ProgressView(value: service.loadProgress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 240)
                    Text("Downloading… \(Int(service.loadProgress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if isLoadedAndSelected {
                    Label("Loaded", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if isLoadingThisModel {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.6)
                        Text("Loading…").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                actionButton
                if isDownloaded && !isDownloading {
                    Menu {
                        Button(role: .destructive) {
                            deleteModel()
                        } label: {
                            Label("Delete from device", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if isDownloading || isLoadingThisModel {
            ProgressView()
                .scaleEffect(0.7)
        } else if !isDownloaded {
            Button {
                downloadModel()
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
                    .font(.callout)
            }
            .buttonStyle(.pill)
        } else if !isLoadedAndSelected {
            Button {
                selectAndLoad()
            } label: {
                Label("Use", systemImage: "checkmark.circle")
                    .font(.callout)
            }
            .buttonStyle(.pill)
        }
    }

    private func deleteModel() {
        do {
            try service.deleteModel(modelID: model.id)
            if settings.selectedGrammarModelID == model.id {
                settings.selectedGrammarModelID = GrammarCorrectionModel.defaultModelID
            }
        } catch {
            print("Failed to delete grammar model: \(error)")
        }
    }

    private func downloadModel() {
        settings.selectedGrammarModelID = model.id
        Task {
            do {
                try await service.loadModel(modelID: model.id)
            } catch {
                print("Grammar model download failed: \(error)")
            }
        }
    }

    private func selectAndLoad() {
        settings.selectedGrammarModelID = model.id
        Task { try? await service.loadModel(modelID: model.id) }
    }
}

private struct AppleGrammarModelRow: View {
    let model: GrammarCorrectionModel
    @Bindable var settings: AppSettings
    private var service: GrammarCorrectionService { GrammarCorrectionService.shared }

    private var availability: GrammarBackendAvailability { service.availability(for: model.id) }
    private var isLoaded: Bool { service.isModelLoaded && service.loadedModelID == model.id }
    private var isLoading: Bool { service.isLoadingModel && service.loadedModelID != model.id }

    var body: some View {
        let availability = self.availability
        HStack(spacing: 12) {
            Image(systemName: "apple.intelligence")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(.body)
                Text("\(model.provider) · No download")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                switch availability {
                case .available, .requiresDownload:
                    if isLoaded {
                        Label("Loaded", systemImage: "checkmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else if isLoading {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.6)
                            Text("Loading…").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                case .unavailable(let reason, _):
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            actionButton(availability)
        }
    }

    @ViewBuilder
    private func actionButton(_ availability: GrammarBackendAvailability) -> some View {
        switch availability {
        case .available, .requiresDownload:
            if isLoading {
                ProgressView().scaleEffect(0.7)
            } else if !isLoaded {
                Button {
                    settings.selectedGrammarModelID = model.id
                    Task { try? await service.loadModel(modelID: model.id) }
                } label: {
                    Label("Use", systemImage: "checkmark.circle")
                        .font(.callout)
                }
                .buttonStyle(.pill)
            }
        case .unavailable(_, let settingsURL):
            if let settingsURL {
                Button {
                    if !NSWorkspace.shared.open(settingsURL),
                       let fallback = URL(string: "x-apple.systempreferences:") {
                        NSWorkspace.shared.open(fallback)
                    }
                } label: {
                    Label("Open Settings", systemImage: "gear")
                        .font(.callout)
                }
                .buttonStyle(.pill)
            }
        }
    }
}

/// One row for every hosted provider: pick the provider, type a model name, paste a key. The
/// key goes to the keychain, never to defaults or logs; the row says plainly that the text
/// leaves the Mac.
private struct HostedGrammarRow: View {
    @Bindable var settings: AppSettings
    private var service: GrammarCorrectionService { GrammarCorrectionService.shared }

    @State private var provider: HostedProvider = HostedProvider(
        rawValue: UserDefaults.standard.string(forKey: HostedProvider.selectedKey) ?? "") ?? .groq
    @State private var keyDraft = ""
    @State private var modelDraft = ""
    @State private var notice: String?
    @State private var hasKey = false

    private var backend: HostedGrammarBackend { service.hostedBackend(for: provider) }
    private var isLoaded: Bool { service.isModelLoaded && service.loadedModelID == provider.modelID }
    private var isLoading: Bool { service.isLoadingModel && settings.selectedGrammarModelID == provider.modelID }
    private var isSelected: Bool { settings.selectedGrammarModelID == provider.modelID }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "cloud")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hosted provider").font(.body)
                    Text("Clean-up through a service with your own API key. Everything you dictate is sent to it; the key is kept in your keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    Picker("Provider", selection: $provider) {
                        ForEach(HostedProvider.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Link("Get an API key", destination: provider.keyPageURL)
                        .font(.caption)
                }

                HStack(spacing: 8) {
                    Text("Model").font(.callout)
                    TextField(provider.defaultModel, text: $modelDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                        .onSubmit { backend.setModel(modelDraft) }
                        .onChange(of: modelDraft) { backend.setModel(modelDraft) }
                }

                HStack(spacing: 8) {
                    SecureField(hasKey ? "Key saved — paste a new one to replace it" : "Paste your API key", text: $keyDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                        .onSubmit(saveKey)
                    Button("Save") { saveKey() }
                        .buttonStyle(.pillSmall)
                        .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if hasKey {
                        Button("Remove") { removeKey() }.buttonStyle(.pillSmall)
                    }
                }

                if isLoaded {
                    Label("Loaded", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if isLoading {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.6)
                        Text("Loading…").font(.caption).foregroundStyle(.secondary)
                    }
                } else if let notice {
                    Text(notice).font(.caption).foregroundStyle(.orange)
                }
            }

            Spacer()

            if hasKey, !isLoaded, !isLoading {
                Button {
                    settings.selectedGrammarModelID = provider.modelID
                    Task { await load() }
                } label: {
                    Label("Use", systemImage: "checkmark.circle")
                        .font(.callout)
                }
                .buttonStyle(.pill)
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: provider) {
            UserDefaults.standard.set(provider.rawValue, forKey: HostedProvider.selectedKey)
            keyDraft = ""
            refresh()
        }
    }

    private func refresh() {
        hasKey = backend.hasKey
        modelDraft = backend.customModel
        notice = nil
    }

    private func saveKey() {
        do {
            try backend.setKey(keyDraft)
            keyDraft = ""
            hasKey = backend.hasKey
            notice = nil
            // The key for the provider in use replaces the one the loaded backend held.
            if isSelected { Task { await load() } }
        } catch {
            notice = error.localizedDescription
        }
    }

    private func removeKey() {
        do {
            try backend.setKey(nil)
            hasKey = false
            if isSelected { service.unloadModel() }
        } catch {
            notice = error.localizedDescription
        }
    }

    private func load() async {
        do {
            try await service.loadModel(modelID: provider.modelID)
            notice = nil
        } catch {
            notice = error.localizedDescription
        }
    }
}

private struct ModesList: View {
    let store: ModeStore
    @State private var editing: DictationMode?
    @State private var isAdding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Modes").font(.body)
                Spacer()
                Button("Add Mode…") { isAdding = true }.buttonStyle(.pillSmall)
            }
            Text("The app in front when you press the shortcut picks the mode; Default covers the rest.")
                .font(.caption).foregroundStyle(.secondary)
            if store.fileWasSetAside {
                Text("A damaged modes file was set aside; modes started again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(store.modes) { mode in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode.name)
                        Text(mode.isDefault ? "All other apps" : (mode.appBundleIDs.isEmpty ? "No apps yet" : appNames(mode.appBundleIDs)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !mode.cleanUp { Text("Raw").font(.caption).foregroundStyle(.secondary) }
                    Button("Edit") { editing = mode }.buttonStyle(.pillSmall)
                }
                .padding(.vertical, 2)
            }
        }
        .sheet(item: $editing) { mode in ModeEditor(store: store, mode: mode) }
        .sheet(isPresented: $isAdding) {
            ModeEditor(store: store, mode: DictationMode(id: UUID(), name: "", instructions: "", cleanUp: true, appBundleIDs: []), isNew: true)
        }
    }

    private func appNames(_ ids: [String]) -> String {
        ids.map { ModeEditor.displayName(forBundleID: $0) }.joined(separator: ", ")
    }
}
