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

    var body: some View {
        SettingsSectionContainer(title: "Transcription Model") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    if hasDownloadedModels {
                        Picker("Model", selection: $settings.selectedModelID) {
                            ForEach(downloadService.downloadedModels, id: \.self) { variant in
                                Text(displayName(for: variant))
                                    .tag(variant)
                            }
                        }
                        .labelsHidden()
                        .onChange(of: settings.selectedModelID) { _, newValue in
                            loadSelectedModel(newValue)
                        }
                    } else {
                        Text("No models downloaded")
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        showingModelDownloadModal = true
                    } label: {
                        Label("More Models", systemImage: "arrow.down.circle")
                    }
                }

                // Model status
                if transcriptionService.isModelLoaded {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Model loaded and ready")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

    private func displayName(for variant: String) -> String {
        variant
            .replacingOccurrences(of: "openai_whisper-", with: "")
            .replacingOccurrences(of: "whisper-", with: "")
            .replacingOccurrences(of: "-en", with: " (English)")
            .capitalized
    }

    private func loadSelectedModel(_ variant: String) {
        guard !variant.isEmpty else { return }

        Task {
            do {
                try await transcriptionService.loadModel(variant: variant)
            } catch {
                print("Failed to load model: \(error.localizedDescription)")
            }
        }
    }
}
