//
//  ModelDownloadModal.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import SwiftUI

struct ModelDownloadModal: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var settings: AppSettings

    @State private var availableModels: [UnifiedModelInfo] = []
    @State private var isLoading = true
    @State private var downloadError: String?

    private var downloadService: ModelDownloadService { ModelDownloadService.shared }

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
            if isLoading {
                VStack {
                    ProgressView()
                    Text("Loading available models...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(sortedModels) { model in
                            UnifiedModelRow(
                                model: model,
                                isDownloaded: downloadService.isModelDownloaded(model.id),
                                isDownloading: downloadService.activeDownloads[model.id] != nil,
                                downloadProgress: downloadService.progress(for: model.id),
                                onDownload: { startDownload(model) },
                                onDelete: { deleteModel(model) },
                                onSelect: { selectModel(model) },
                                isSelected: settings.selectedModelID == model.id
                            )
                        }
                    }
                    .padding(20)
                }
            }

            Divider()

            // Error message
            if let error = downloadError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Dismiss") {
                        downloadError = nil
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.orange.opacity(0.1))

                Divider()
            }

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
        .task {
            await loadModels()
        }
    }

    private var sortedModels: [UnifiedModelInfo] {
        availableModels.sorted { model1, model2 in
            let downloaded1 = downloadService.isModelDownloaded(model1.id)
            let downloaded2 = downloadService.isModelDownloaded(model2.id)

            // Downloaded models first
            if downloaded1 != downloaded2 {
                return downloaded1
            }
            // Recommended models next
            if model1.isRecommended != model2.isRecommended {
                return model1.isRecommended
            }
            // Then by provider (Parakeet first)
            if model1.provider != model2.provider {
                return model1.provider == .fluidAudio
            }
            return model1.displayName < model2.displayName
        }
    }

    private func loadModels() async {
        isLoading = true
        availableModels = await downloadService.fetchAvailableModels()
        await downloadService.refreshDownloadedModels()
        isLoading = false
    }

    private func startDownload(_ model: UnifiedModelInfo) {
        downloadError = nil
        Task {
            do {
                try await downloadService.downloadModel(modelID: model.id)
            } catch {
                let errorMessage = error.localizedDescription
                print("Download failed: \(errorMessage)")

                if errorMessage.contains("hostname could not be found") ||
                   errorMessage.contains("network connection was lost") ||
                   errorMessage.contains("Internet connection appears to be offline") {
                    downloadError = "Network error: Unable to reach servers. Please check your internet connection and VPN settings."
                } else {
                    downloadError = "Download failed: \(errorMessage)"
                }
            }
        }
    }

    private func deleteModel(_ model: UnifiedModelInfo) {
        Task {
            try? await downloadService.deleteModel(modelID: model.id)
        }
    }

    private func selectModel(_ model: UnifiedModelInfo) {
        settings.selectedModelID = model.id
    }
}

struct UnifiedModelRow: View {
    let model: UnifiedModelInfo
    let isDownloaded: Bool
    let isDownloading: Bool
    let downloadProgress: Double
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onSelect: () -> Void
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 16) {
            // Status icon
            ZStack {
                if isDownloaded {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "checkmark.circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .green)
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
                    Text(model.displayName)
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

                    // Provider badge
                    Text(model.provider.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .foregroundStyle(.secondary)
                        .clipShape(Capsule())
                }

                HStack(spacing: 12) {
                    Label(model.sizeDescription, systemImage: "internaldrive")

                    if case .englishOnly = model.languageSupport {
                        Label("English", systemImage: "globe")
                    } else {
                        Label("Multilingual", systemImage: "globe")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer()

            // Action button
            if isDownloaded {
                HStack(spacing: 8) {
                    if !isSelected {
                        Button {
                            onSelect()
                        } label: {
                            Text("Select")
                                .font(.subheadline)
                        }
                    } else {
                        Text("Active")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

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
                }
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
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }
}

#Preview {
    @Previewable @State var settings = AppSettings()

    ModelDownloadModal(settings: settings)
        .frame(width: 550, height: 500)
}
