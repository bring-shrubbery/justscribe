//
//  OnboardingView.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 25/01/2026.
//

import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @Bindable var settings: AppSettings

    @State private var currentStep: OnboardingStep = .welcome
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var downloadError: String?
    @State private var selectedModel: ModelDownloadService.WhisperModelInfo?

    private var downloadService: ModelDownloadService { ModelDownloadService.shared }

    enum OnboardingStep {
        case welcome
        case selectModel
        case downloading
        case complete
    }

    var body: some View {
        VStack(spacing: 0) {
            // Content
            Group {
                switch currentStep {
                case .welcome:
                    welcomeStep
                case .selectModel:
                    selectModelStep
                case .downloading:
                    downloadingStep
                case .complete:
                    completeStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 480, height: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Welcome Step

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 8) {
                Text("Welcome to JustScribe")
                    .font(.title)
                    .fontWeight(.semibold)

                Text("Voice transcription at your fingertips")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Text("To get started, you'll need to download a transcription model. This only takes a minute.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Button {
                withAnimation {
                    currentStep = .selectModel
                }
            } label: {
                Text("Get Started")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 60)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Select Model Step

    private var selectModelStep: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Choose a Model")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("We recommend starting with Base for a good balance of speed and accuracy.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(recommendedModels) { model in
                        ModelSelectionRow(
                            model: model,
                            isSelected: selectedModel?.variant == model.variant,
                            onSelect: { selectedModel = model }
                        )
                    }
                }
                .padding(.horizontal, 24)
            }

            if let error = downloadError {
                VStack(spacing: 4) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)

                    if error.contains("hostname") || error.contains("network") {
                        Text("Check your internet connection and VPN settings")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
            }

            HStack(spacing: 12) {
                Button("Back") {
                    withAnimation {
                        currentStep = .welcome
                    }
                }
                .buttonStyle(.bordered)

                Button {
                    startDownload()
                } label: {
                    Text("Download")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedModel == nil)
            }
            .padding(.horizontal, 60)
            .padding(.bottom, 24)
        }
    }

    private var recommendedModels: [ModelDownloadService.WhisperModelInfo] {
        [
            .init(variant: "openai_whisper-tiny", displayName: "Tiny", sizeDescription: "~75 MB", isRecommended: false),
            .init(variant: "openai_whisper-base", displayName: "Base", sizeDescription: "~142 MB", isRecommended: true),
            .init(variant: "openai_whisper-small", displayName: "Small", sizeDescription: "~466 MB", isRecommended: false),
        ]
    }

    // MARK: - Downloading Step

    private var downloadingStep: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            VStack(spacing: 8) {
                Text("Downloading \(selectedModel?.displayName ?? "Model")...")
                    .font(.title3)
                    .fontWeight(.medium)

                Text("\(Int(downloadProgress * 100))%")
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: downloadProgress)
                .frame(width: 200)

            Text("This may take a few minutes depending on your connection.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    // MARK: - Complete Step

    private var completeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)

            VStack(spacing: 8) {
                Text("You're All Set!")
                    .font(.title)
                    .fontWeight(.semibold)

                Text("Press \(shortcutDescription) anywhere to start transcribing.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                isPresented = false
            } label: {
                Text("Start Using JustScribe")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 60)
            .padding(.bottom, 32)
        }
    }

    private var shortcutDescription: String {
        "Ctrl + Shift + Space"
    }

    // MARK: - Actions

    private func startDownload() {
        guard let model = selectedModel else { return }

        downloadError = nil
        isDownloading = true

        withAnimation {
            currentStep = .downloading
        }

        Task {
            do {
                _ = try await downloadService.downloadModel(variant: model.variant)

                // Update progress periodically
                while downloadService.activeDownloads[model.variant] != nil {
                    downloadProgress = downloadService.progress(for: model.variant)
                    try? await Task.sleep(for: .milliseconds(100))
                }

                // Set as selected model
                settings.selectedModelID = model.variant

                // Load the model
                try? await TranscriptionService.shared.loadModel(variant: model.variant)

                withAnimation {
                    currentStep = .complete
                }
            } catch {
                downloadError = error.localizedDescription
                withAnimation {
                    currentStep = .selectModel
                }
            }

            isDownloading = false
        }
    }
}

struct ModelSelectionRow: View {
    let model: ModelDownloadService.WhisperModelInfo
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
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
                    }

                    Text(model.sizeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(12)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var isPresented = true
    @Previewable @State var settings = AppSettings()

    OnboardingView(isPresented: $isPresented, settings: settings)
}
