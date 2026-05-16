//
//  GrammarCorrectionSettingsSection.swift
//  justscribe
//

import SwiftUI

struct GrammarCorrectionSettingsSection: View {
    @Bindable var settings: AppSettings
    private var service: GrammarCorrectionService { GrammarCorrectionService.shared }

    var body: some View {
        SettingsSectionContainer(title: "Grammar Correction") {
            VStack(spacing: 12) {
                ToggleSettingsRow(
                    title: "Enable Grammar Correction",
                    subtitle: "Fix grammar, spelling, and punctuation in transcriptions",
                    systemImage: "text.badge.checkmark",
                    isOn: Binding(
                        get: { settings.grammarCorrectionEnabled },
                        set: { newValue in
                            settings.grammarCorrectionEnabled = newValue
                            UserDefaults.standard.set(newValue, forKey: AppSettings.grammarCorrectionEnabledKey)
                            if !newValue {
                                service.unloadModel()
                            } else if !settings.selectedGrammarModelID.isEmpty,
                                      service.isModelDownloaded(settings.selectedGrammarModelID) {
                                let modelID = settings.selectedGrammarModelID
                                Task { try? await service.loadModel(modelID: modelID) }
                            }
                        }
                    )
                )

                if settings.grammarCorrectionEnabled {
                    ForEach(GrammarCorrectionModel.allModels) { model in
                        Divider()
                        AvailableGrammarModelRow(model: model, settings: settings)
                    }
                }
            }
        }
    }
}

private struct AvailableGrammarModelRow: View {
    let model: GrammarCorrectionModel
    @Bindable var settings: AppSettings
    private var service: GrammarCorrectionService { GrammarCorrectionService.shared }

    private var isDownloaded: Bool { service.isModelDownloaded(model.id) }
    private var isDownloading: Bool { service.activelyDownloadingModelID == model.id }
    private var isLoadingThisModel: Bool {
        service.isLoadingModel && service.loadedModelID != model.id && !isDownloading
    }
    private var isLoadedAndSelected: Bool {
        service.isModelLoaded && service.loadedModelID == model.id
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
                Text("\(model.provider) · \(model.approximateSize) · RAM \(model.approximateRAM)")
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
                settings.selectedGrammarModelID = ""
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
