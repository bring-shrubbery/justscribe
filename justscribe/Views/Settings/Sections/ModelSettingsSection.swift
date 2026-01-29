//
//  ModelSettingsSection.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import SwiftUI

struct ModelSettingsSection: View {
    @Bindable var settings: AppSettings
    @Binding var showingModelDownloadModal: Bool

    private var downloadService: ModelDownloadService { ModelDownloadService.shared }
    private var transcriptionService: TranscriptionService { TranscriptionService.shared }

    private var hasDownloadedModels: Bool {
        !downloadService.downloadedModels.isEmpty
    }

    private var isSelectedModelDownloaded: Bool {
        downloadService.isModelDownloaded(settings.selectedModelID)
    }

    private var downloadedModelsList: [UnifiedModelInfo] {
        downloadService.downloadedModels.compactMap { modelID in
            UnifiedModelInfo.model(forID: modelID)
        }
    }

    private var selectedModelDisplayName: String {
        if let model = UnifiedModelInfo.model(forID: settings.selectedModelID) {
            return "\(model.displayName) (\(model.provider.displayName))"
        }
        return "Select a model"
    }

    var body: some View {
        SettingsSectionContainer(title: "Transcription Model") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack(alignment: .leading) {
                        if hasDownloadedModels {
                            // Background that expands to fill space
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                                )

                            // Menu overlay
                            Menu {
                                ForEach(downloadedModelsList) { model in
                                    Button {
                                        settings.selectedModelID = model.id
                                        loadSelectedModel(model.id)
                                    } label: {
                                        if settings.selectedModelID == model.id {
                                            Label("\(model.displayName) (\(model.provider.displayName))", systemImage: "checkmark")
                                        } else {
                                            Text("\(model.displayName) (\(model.provider.displayName))")
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(selectedModelDisplayName)
                                        .lineLimit(1)
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("No models downloaded")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 28)

                    Button {
                        showingModelDownloadModal = true
                    } label: {
                        Label("More Models", systemImage: "arrow.down.circle")
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }

                // Model status
                if transcriptionService.isModelLoaded {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        if let provider = transcriptionService.loadedProvider {
                            Text("\(provider.displayName) model loaded and ready")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Model loaded and ready")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if transcriptionService.state == .loadingModel {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Loading model...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if !settings.selectedModelID.isEmpty && isSelectedModelDownloaded {
                    Button {
                        loadSelectedModel(settings.selectedModelID)
                    } label: {
                        Label("Load Model", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                }
            }
        }
    }

    private func loadSelectedModel(_ modelID: String) {
        guard !modelID.isEmpty else { return }

        Task {
            do {
                try await transcriptionService.loadModel(unifiedID: modelID)
            } catch {
                print("Failed to load model: \(error.localizedDescription)")
            }
        }
    }
}
