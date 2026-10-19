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

/// One entry of the "Clean up with" list. Hosted providers share one entry (the provider is
/// picked inside its set-up), each command-line agent has its own.
private enum CleanUpChoice: Hashable, Identifiable {
    case apple
    case mlx
    case hosted
    case cli(CLIAgent)

    var id: Self { self }

    static let all: [CleanUpChoice] = [.apple, .mlx, .hosted] + CLIAgent.allCases.map { .cli($0) }

    var name: String {
        switch self {
        case .apple: return GrammarCorrectionModel.appleFoundation.displayName
        case .mlx: return "\(GrammarCorrectionModel.llama3_1_8b_4bit.displayName) on this Mac"
        case .hosted: return "Hosted provider"
        case .cli(let agent): return agent.displayName
        }
    }

    var caption: String {
        switch self {
        case .apple: return "Built into macOS · No download"
        case .mlx:
            let model = GrammarCorrectionModel.llama3_1_8b_4bit
            return [model.provider, model.approximateSize.map { "\($0) download" }, model.approximateRAM.map { "\($0) RAM" }]
                .compactMap { $0 }.joined(separator: " · ")
        case .hosted: return HostedProvider.allCases.map(\.displayName).joined(separator: ", ")
        case .cli(let agent): return "Command-line tool · \(agent.accountName)"
        }
    }

    var systemImage: String {
        switch self {
        case .apple: return "apple.intelligence"
        case .mlx: return "shippingbox"
        case .hosted: return "cloud"
        case .cli: return "terminal"
        }
    }
}

/// Clean-up settings: the switch, the list of ways to clean up with each one's readiness at a
/// glance, and the set-up of the one picked. Only one is in use at a time, so only one is
/// shown in full.
struct CleanUpSettingsSection: View {
    @Bindable var settings: AppSettings
    private var service: GrammarCorrectionService { GrammarCorrectionService.shared }

    /// The entry whose set-up is shown; nil follows the one in use.
    @State private var focused: CleanUpChoice?
    @State private var hostedProvider: HostedProvider = HostedProvider(
        rawValue: UserDefaults.standard.string(forKey: HostedProvider.selectedKey) ?? "") ?? .groq
    /// Where each agent's tool was found, read once: locating probes the file system.
    @State private var installedAgents: [CLIAgent: String] = [:]

    var body: some View {
        Section {
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
        }
        .onAppear(perform: locateAgents)

        if settings.grammarCorrectionEnabled {
            Section {
                ForEach(CleanUpChoice.all) { choice in
                    chooserRow(choice)
                }
            } header: {
                Text("Clean up with")
            } footer: {
                Text("One is used at a time. Pick a row to set it up or switch to it.")
            }

            Section(shownChoice.name) {
                switch shownChoice {
                case .apple:
                    AppleGrammarCard(model: .appleFoundation, settings: settings)
                case .mlx:
                    MLXGrammarCard(model: .llama3_1_8b_4bit, settings: settings)
                case .hosted:
                    HostedGrammarCard(settings: settings, provider: $hostedProvider)
                case .cli(let agent):
                    CLIGrammarCard(agent: agent, settings: settings, installedAt: installedAgents[agent])
                }
            }
        }
    }

    // MARK: Chooser

    private var shownChoice: CleanUpChoice { focused ?? choiceInUse }

    /// The entry `selectedGrammarModelID` points at.
    private var choiceInUse: CleanUpChoice {
        let id = settings.selectedGrammarModelID
        if id.hasPrefix(HostedProvider.modelIDPrefix) { return .hosted }
        if let agent = CLIAgent.allCases.first(where: { $0.modelID == id }) { return .cli(agent) }
        if id == GrammarCorrectionModel.llama3_1_8b_4bit.id { return .mlx }
        return .apple
    }

    private func modelID(for choice: CleanUpChoice) -> String {
        switch choice {
        case .apple: return GrammarCorrectionModel.appleFoundation.id
        case .mlx: return GrammarCorrectionModel.llama3_1_8b_4bit.id
        case .hosted: return hostedProvider.modelID
        case .cli(let agent): return agent.modelID
        }
    }

    /// Whether picking the row can switch to it right away, without a download, key or install.
    private func isReady(_ choice: CleanUpChoice) -> Bool {
        switch choice {
        case .apple:
            if case .unavailable = service.availability(for: modelID(for: choice)) { return false }
            return true
        case .mlx: return service.isReadyToUse(modelID(for: choice))
        case .hosted: return service.hostedBackend(for: hostedProvider).hasKey
        case .cli(let agent): return installedAgents[agent] != nil
        }
    }

    private struct RowStatus {
        var text: String
        var color: Color = .secondary
        var systemImage: String?
    }

    private func status(for choice: CleanUpChoice) -> RowStatus {
        let id = modelID(for: choice)
        if choice == choiceInUse {
            if let failure = service.lastFailure, failure.modelID == settings.selectedGrammarModelID {
                return RowStatus(text: "Failed", color: .orange, systemImage: "exclamationmark.triangle.fill")
            }
            if service.isModelLoaded && service.loadedModelID == settings.selectedGrammarModelID {
                if choice == .hosted, settings.selectedGrammarModelID != id,
                   let provider = HostedProvider(rawValue: String(settings.selectedGrammarModelID.dropFirst(HostedProvider.modelIDPrefix.count))) {
                    return RowStatus(text: "\(provider.displayName) in use", color: .accentColor, systemImage: "checkmark.circle.fill")
                }
                return RowStatus(text: "In use", color: .accentColor, systemImage: "checkmark.circle.fill")
            }
            if service.isLoadingModel { return RowStatus(text: "Loading…") }
            return RowStatus(text: "Selected")
        }
        switch choice {
        case .apple:
            if case .unavailable = service.availability(for: id) { return RowStatus(text: "Not available", color: .orange) }
            return RowStatus(text: "Ready")
        case .mlx:
            if service.activelyDownloadingModelID == id { return RowStatus(text: "Downloading \(Int(service.loadProgress * 100))%") }
            return RowStatus(text: isReady(choice) ? "Ready" : "Needs a download")
        case .hosted:
            return RowStatus(text: isReady(choice) ? "Ready" : "Needs an API key")
        case .cli:
            return RowStatus(text: isReady(choice) ? "Ready" : "Not installed")
        }
    }

    private func chooserRow(_ choice: CleanUpChoice) -> some View {
        let status = status(for: choice)
        let isShown = choice == shownChoice
        return HStack(spacing: 12) {
            Image(systemName: choice.systemImage)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(choice.name)
                    .font(.body)
                Text(choice.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .opacity(isReady(choice) || choice == choiceInUse ? 1 : 0.6)
            Spacer()
            HStack(spacing: 4) {
                if let symbol = status.systemImage {
                    Image(systemName: symbol)
                }
                Text(status.text)
            }
            .font(.caption)
            .foregroundStyle(status.color)
        }
        .contentShape(Rectangle())
        .onTapGesture { pick(choice) }
        .listRowBackground(isShown ? Color.accentColor.opacity(0.12) : nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isShown ? [.isButton, .isSelected] : .isButton)
    }

    /// Shows the row's set-up and, when it is ready, switches to it.
    private func pick(_ choice: CleanUpChoice) {
        focused = choice
        guard choice != choiceInUse, isReady(choice) else { return }
        let id = modelID(for: choice)
        settings.selectedGrammarModelID = id
        Task { try? await service.loadModel(modelID: id) }
    }

    private func locateAgents() {
        var found: [CLIAgent: String] = [:]
        for agent in CLIAgent.allCases {
            found[agent] = service.cliBackend(for: agent).executablePath
        }
        installedAgents = found
    }
}

// MARK: - Set-up cards

/// A "Loaded" / "Loading…" line for the model a card is about, or nothing.
private struct LoadStateLabel: View {
    let modelID: String
    private var service: GrammarCorrectionService { GrammarCorrectionService.shared }

    var body: some View {
        if service.isModelLoaded && service.loadedModelID == modelID {
            Label("Loaded", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(.green)
        } else if service.isLoadingModel && service.loadedModelID != modelID {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.6)
                Text("Loading…").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct UseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Use", systemImage: "checkmark.circle")
                .font(.callout)
        }
        .buttonStyle(.pill)
    }
}

private struct AppleGrammarCard: View {
    let model: GrammarCorrectionModel
    @Bindable var settings: AppSettings
    private var service: GrammarCorrectionService { GrammarCorrectionService.shared }

    private var availability: GrammarBackendAvailability { service.availability(for: model.id) }
    private var isLoaded: Bool { service.isModelLoaded && service.loadedModelID == model.id }
    private var isLoading: Bool { service.isLoadingModel && service.loadedModelID != model.id }

    var body: some View {
        let availability = self.availability
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Grammar, spelling and punctuation are fixed by the Apple model on this Mac. Nothing leaves it and there is nothing to download.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                switch availability {
                case .available, .requiresDownload:
                    LoadStateLabel(modelID: model.id)
                case .unavailable(let reason, _):
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
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
                UseButton {
                    settings.selectedGrammarModelID = model.id
                    Task { try? await service.loadModel(modelID: model.id) }
                }
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

private struct MLXGrammarCard: View {
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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(model.displayName) · \(model.provider)")
                    .font(.body)
                Text("Runs entirely on this Mac. \(model.approximateSize ?? "") on disk, about \(model.approximateRAM ?? "") of memory while loaded; the first load after the download takes a moment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if isDownloading {
                    ProgressView(value: service.loadProgress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 240)
                    Text("Downloading… \(Int(service.loadProgress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    LoadStateLabel(modelID: model.id)
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
            UseButton { selectAndLoad() }
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

/// Set-up for the hosted providers: pick the provider, type a model name, paste a key. The key
/// goes to the keychain, never to defaults or logs; the card says plainly that the text leaves
/// the Mac.
private struct HostedGrammarCard: View {
    @Bindable var settings: AppSettings
    @Binding var provider: HostedProvider
    private var service: GrammarCorrectionService { GrammarCorrectionService.shared }

    @State private var keyDraft = ""
    @State private var modelDraft = ""
    @State private var notice: String?
    @State private var hasKey = false

    private var backend: HostedGrammarBackend { service.hostedBackend(for: provider) }
    private var lastFailure: String? {
        service.lastFailure.flatMap { $0.modelID == provider.modelID ? "Last clean-up failed: \($0.message)" : nil }
    }
    private var isLoaded: Bool { service.isModelLoaded && service.loadedModelID == provider.modelID }
    private var isLoading: Bool { service.isLoadingModel && settings.selectedGrammarModelID == provider.modelID }
    private var isSelected: Bool { settings.selectedGrammarModelID == provider.modelID }

    var body: some View {
        LabeledContent("Provider") {
            HStack(spacing: 10) {
                Picker("Provider", selection: $provider) {
                    ForEach(HostedProvider.allCases) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Link("Get an API key", destination: provider.keyPageURL)
                    .font(.caption)
            }
        }

        LabeledContent("Model") {
            TextField(provider.defaultModel, text: $modelDraft)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
                .onSubmit { backend.setModel(modelDraft) }
                .onChange(of: modelDraft) {
                    backend.setModel(modelDraft)
                    service.clearLastFailure()
                }
        }

        LabeledContent("API key") {
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
        }

        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Everything you dictate is sent to \(provider.displayName). The key is kept in your keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                LoadStateLabel(modelID: provider.modelID)
                if let notice = notice ?? lastFailure {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if hasKey, !isLoaded, !isLoading {
                UseButton {
                    settings.selectedGrammarModelID = provider.modelID
                    Task { await load() }
                }
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

/// Set-up for a coding agent's command-line tool: where it is, which model, a way to try it,
/// since a sign-in problem shows only on a request.
private struct CLIGrammarCard: View {
    let agent: CLIAgent
    @Bindable var settings: AppSettings
    let installedAt: String?
    private var service: GrammarCorrectionService { GrammarCorrectionService.shared }

    @State private var models: [CLIModelOption] = []
    @State private var modelChoice = ""
    @State private var customDraft = ""
    @State private var notice: String?
    @State private var isTrying = false

    private var backend: CLIGrammarBackend { service.cliBackend(for: agent) }
    /// Why the last dictation's clean-up through this agent failed, which the island sent the user here for.
    private var lastFailure: String? {
        service.lastFailure.flatMap { $0.modelID == agent.modelID ? "Last clean-up failed: \($0.message)" : nil }
    }
    private var isLoaded: Bool { service.isModelLoaded && service.loadedModelID == agent.modelID }
    private var isLoading: Bool { service.isLoadingModel && settings.selectedGrammarModelID == agent.modelID }

    var body: some View {
        if let installedAt {
            LabeledContent("Found at") {
                Text(installedAt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            LabeledContent("Model") {
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 8) {
                        Picker("Model", selection: $modelChoice) {
                            ForEach(models) { model in
                                Text(label(for: model)).tag(model.id)
                            }
                            Divider()
                            Text("Custom…").tag(Self.customTag)
                        }
                        .labelsHidden()
                        .fixedSize()
                        .onChange(of: modelChoice) {
                            backend.setModel(modelChoice == Self.customTag ? customDraft : modelChoice)
                            service.clearLastFailure()
                        }
                        if isLoaded {
                            Button(isTrying ? "Trying…" : "Try It") { tryIt() }
                                .buttonStyle(.pillSmall)
                                .disabled(isTrying)
                        }
                    }
                    if let chosenModelDetail {
                        Text(chosenModelDetail)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if modelChoice == Self.customTag {
                        TextField(agent.defaultModel, text: $customDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 200)
                            .onChange(of: customDraft) {
                                backend.setModel(customDraft)
                                service.clearLastFailure()
                            }
                        Text("Any model name `\(agent.commandName) --model` accepts.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Everything you dictate is sent through \(agent.displayName) to \(agent.accountName).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    LoadStateLabel(modelID: agent.modelID)
                    if let notice = notice ?? lastFailure {
                        Text(notice)
                            .font(.caption)
                            .foregroundStyle(notice.hasPrefix("→") ? Color.secondary : Color.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                if !isLoaded, !isLoading {
                    UseButton {
                        settings.selectedGrammarModelID = agent.modelID
                        Task {
                            do {
                                try await service.loadModel(modelID: agent.modelID)
                                notice = nil
                            } catch {
                                notice = error.localizedDescription
                            }
                        }
                    }
                }
            }
            .onAppear(perform: readModel)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Not installed, or not where JustScribe can see it. Install it and open Settings again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link("About \(agent.displayName)", destination: agent.installURL)
                    .font(.caption)
            }
        }
    }

    private func readModel() {
        models = backend.availableModels
        let custom = backend.customModel
        if custom.isEmpty {
            modelChoice = agent.defaultModel
        } else if models.contains(where: { $0.id == custom }) {
            modelChoice = custom
        } else {
            customDraft = custom
            modelChoice = Self.customTag
        }
    }

    /// The picker's tag for a model name typed by hand; no model is called this.
    private static let customTag = "\u{0}custom"

    private func label(for model: CLIModelOption) -> String {
        model.id == agent.defaultModel ? "\(model.name) (Default)" : model.name
    }

    private var chosenModelDetail: String? {
        guard let detail = models.first(where: { $0.id == modelChoice })?.detail, !detail.isEmpty else { return nil }
        return detail
    }

    /// Runs one small correction through the tool, so a sign-in problem shows here rather
    /// than on the first dictation.
    private func tryIt() {
        isTrying = true
        notice = nil
        Task {
            defer { isTrying = false }
            do {
                let sample = "this is a quick test of the clean up it should fix the capitals and punctuation"
                let result = try await service.correctGrammar(sample, instructions: DictationMode.defaultInstructions)
                notice = "→ " + result
            } catch {
                notice = error.localizedDescription
            }
        }
    }
}
