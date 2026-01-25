//
//  ModelSettingsSection.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import SwiftUI
import SwiftData

struct ModelSettingsSection: View {
    @Bindable var settings: AppSettings
    @Binding var showingModelDownloadModal: Bool

    @Query private var downloadedModels: [TranscriptionModel]

    private var availableModels: [TranscriptionModel] {
        downloadedModels.filter { $0.isDownloaded }
    }

    private var selectedModel: TranscriptionModel? {
        downloadedModels.first { $0.id == settings.selectedModelID }
    }

    var body: some View {
        SettingsSectionContainer(title: "Transcription Model") {
            HStack(spacing: 12) {
                Picker("Model", selection: $settings.selectedModelID) {
                    if availableModels.isEmpty {
                        Text("No models downloaded").tag("")
                    } else {
                        ForEach(availableModels) { model in
                            HStack {
                                Text(model.name)
                                if model.isRecommended {
                                    Text("Recommended")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tag(model.id)
                        }
                    }
                }
                .labelsHidden()

                Button {
                    showingModelDownloadModal = true
                } label: {
                    Label("More Models", systemImage: "arrow.down.circle")
                }
            }

            if let model = selectedModel {
                HStack(spacing: 16) {
                    modelInfoBadge(title: "Accuracy", value: model.accuracy.displayName)
                    modelInfoBadge(title: "Speed", value: model.speed.displayName)
                    modelInfoBadge(title: "Size", value: model.formattedSize)
                }
                .padding(.top, 4)
            }
        }
    }

    private func modelInfoBadge(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
