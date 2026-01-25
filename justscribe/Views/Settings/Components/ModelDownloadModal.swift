//
//  ModelDownloadModal.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import SwiftUI
import SwiftData

struct ModelDownloadModal: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var models: [TranscriptionModel]

    @State private var downloadingModelID: String?
    @State private var downloadProgress: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Available Models")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Download models for offline transcription")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            // Model List
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(sortedModels) { model in
                        ModelDownloadRow(
                            model: model,
                            isDownloading: downloadingModelID == model.id,
                            downloadProgress: downloadingModelID == model.id ? downloadProgress : 0,
                            onDownload: { startDownload(model) },
                            onDelete: { deleteModel(model) }
                        )
                    }
                }
                .padding(20)
            }

            Divider()

            // Footer
            HStack {
                Text("Models are stored locally and never leave your device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .onAppear {
            ensureModelsExist()
        }
    }

    private var sortedModels: [TranscriptionModel] {
        models.sorted { model1, model2 in
            // Sort by: downloaded first, then recommended, then by size
            if model1.isDownloaded != model2.isDownloaded {
                return model1.isDownloaded
            }
            if model1.isRecommended != model2.isRecommended {
                return model1.isRecommended
            }
            return model1.size < model2.size
        }
    }

    private func ensureModelsExist() {
        // Create model entries if they don't exist
        for modelInfo in TranscriptionModel.availableModels {
            let existingModels = models.filter { $0.id == modelInfo.id }
            if existingModels.isEmpty {
                let model = TranscriptionModel(
                    id: modelInfo.id,
                    name: modelInfo.name,
                    description: modelInfo.description,
                    size: modelInfo.size,
                    downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(modelInfo.id).bin")!,
                    accuracy: modelInfo.accuracy,
                    speed: modelInfo.speed,
                    isRecommended: modelInfo.recommended
                )
                modelContext.insert(model)
            }
        }
    }

    private func startDownload(_ model: TranscriptionModel) {
        downloadingModelID = model.id
        downloadProgress = 0

        // Simulate download progress for now
        // Will be replaced with actual ModelDownloadService
        Task {
            for i in 1...100 {
                try? await Task.sleep(for: .milliseconds(50))
                await MainActor.run {
                    downloadProgress = Double(i) / 100.0
                }
            }

            await MainActor.run {
                model.isDownloaded = true
                model.downloadProgress = 1.0
                model.localPath = Constants.Storage.modelsDirectory.appendingPathComponent("\(model.id).bin")
                downloadingModelID = nil
            }
        }
    }

    private func deleteModel(_ model: TranscriptionModel) {
        // Delete the model file
        if let path = model.localPath {
            try? FileManager.default.removeItem(at: path)
        }

        model.isDownloaded = false
        model.downloadProgress = 0
        model.localPath = nil
    }
}

struct ModelDownloadRow: View {
    let model: TranscriptionModel
    let isDownloading: Bool
    let downloadProgress: Double
    let onDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Status icon
            ZStack {
                if model.isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if isDownloading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.title2)
            .frame(width: 32)

            // Model info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(model.name)
                        .font(.headline)

                    if model.isRecommended {
                        Text("Recommended")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }

                Text(model.modelDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 12) {
                    Label(model.formattedSize, systemImage: "internaldrive")
                    Label(model.accuracy.displayName, systemImage: "target")
                    Label(model.speed.displayName, systemImage: "speedometer")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer()

            // Action button
            if model.isDownloaded {
                Menu {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 32)
            } else if isDownloading {
                VStack(spacing: 4) {
                    Text("\(Int(downloadProgress * 100))%")
                        .font(.caption)
                        .monospacedDigit()

                    ProgressView(value: downloadProgress)
                        .frame(width: 60)
                }
            } else {
                Button {
                    onDownload()
                } label: {
                    Text("Download")
                        .font(.subheadline)
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    ModelDownloadModal()
        .modelContainer(for: TranscriptionModel.self, inMemory: true)
        .frame(width: 550, height: 500)
}
