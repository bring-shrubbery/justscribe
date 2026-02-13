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
    @State private var selectedModel: UnifiedModelInfo?
    @State private var microphoneGranted = false
    @State private var accessibilityGranted = false
    @State private var isRequestingPermissions = false

    private var downloadService: ModelDownloadService { ModelDownloadService.shared }
    private var permissionsService: PermissionsService { PermissionsService.shared }

    enum OnboardingStep {
        case welcome
        case selectModel
        case downloading
        case permissions
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
                case .permissions:
                    permissionsStep
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
                            isSelected: selectedModel?.id == model.id,
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

    private var recommendedModels: [UnifiedModelInfo] {
        [
            // Parakeet v3 Multilingual is recommended - latest and best
            UnifiedModelInfo(
                provider: .fluidAudio,
                variant: "v3",
                displayName: "Parakeet v3",
                sizeDescription: "~250 MB",
                isRecommended: true,
                languageSupport: .multilingual
            ),
            // Parakeet v2 English-only for maximum English accuracy
            UnifiedModelInfo(
                provider: .fluidAudio,
                variant: "v2",
                displayName: "Parakeet English",
                sizeDescription: "~200 MB",
                isRecommended: false,
                languageSupport: .englishOnly
            ),
            // Whisper Base as fallback option
            UnifiedModelInfo(
                provider: .whisperKit,
                variant: "openai_whisper-base",
                displayName: "Whisper Base",
                sizeDescription: "~142 MB",
                isRecommended: false,
                languageSupport: .multilingual
            ),
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

    // MARK: - Permissions Step

    private var allRequiredPermissionsGranted: Bool {
        microphoneGranted && accessibilityGranted
    }

    private var permissionsStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: allRequiredPermissionsGranted ? "checkmark.shield.fill" : "lock.shield.fill")
                .font(.system(size: 72))
                .foregroundStyle(allRequiredPermissionsGranted ? .green : Color.accentColor)

            VStack(spacing: 8) {
                Text(allRequiredPermissionsGranted ? "Permissions Ready" : "Permissions Required")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(allRequiredPermissionsGranted
                    ? "You're ready to start transcribing."
                    : "JustScribe needs Microphone and Accessibility access to transcribe and type into other apps.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            VStack(spacing: 10) {
                permissionStatusRow(title: "Microphone", granted: microphoneGranted)
                permissionStatusRow(title: "Accessibility", granted: accessibilityGranted)
            }
            .padding(.horizontal, 60)

            Spacer()

            if allRequiredPermissionsGranted {
                Button {
                    withAnimation {
                        currentStep = .complete
                    }
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 60)
                .padding(.bottom, 32)
            } else {
                VStack(spacing: 12) {
                    Button {
                        requestRequiredPermissions()
                    } label: {
                        Text(isRequestingPermissions ? "Requesting..." : "Continue")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isRequestingPermissions)

                    if !microphoneGranted {
                        Button {
                            permissionsService.openMicrophoneSettings()
                        } label: {
                            Text("Open Microphone Settings")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    if !accessibilityGranted {
                        Button {
                            permissionsService.openAccessibilitySettings()
                        } label: {
                            Text("Open Accessibility Settings")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button {
                        withAnimation {
                            currentStep = .complete
                        }
                    } label: {
                        Text("Skip for Now")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 60)
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            refreshPermissionStatus()
        }
    }

    private func permissionStatusRow(title: String, granted: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .secondary)

            Text(title)
                .font(.subheadline)

            Spacer()

            Text(granted ? "Granted" : "Required")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func refreshPermissionStatus() {
        permissionsService.checkMicrophonePermission()
        microphoneGranted = permissionsService.microphoneStatus == .granted

        permissionsService.checkAccessibilityPermission()
        accessibilityGranted = permissionsService.accessibilityStatus == .granted
    }

    private func requestRequiredPermissions() {
        Task { @MainActor in
            guard !isRequestingPermissions else { return }
            isRequestingPermissions = true
            defer { isRequestingPermissions = false }

            NSApp.activate(ignoringOtherApps: true)

            if !microphoneGranted {
                microphoneGranted = await permissionsService.requestMicrophonePermission()
            }

            if !accessibilityGranted {
                permissionsService.requestAccessibilityPermission()
                permissionsService.checkAccessibilityPermission()
                accessibilityGranted = permissionsService.accessibilityStatus == .granted
            }

            if allRequiredPermissionsGranted {
                try? await Task.sleep(for: .milliseconds(500))
                withAnimation {
                    currentStep = .complete
                }
            }
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
        if let config = ShortcutConfig.load() {
            return config.readableDescription
        }
        return "Ctrl + Shift + Space"
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
                try await downloadService.downloadModel(modelID: model.id)

                // Update progress periodically
                while downloadService.activeDownloads[model.id] != nil {
                    downloadProgress = downloadService.progress(for: model.id)
                    try? await Task.sleep(for: .milliseconds(100))
                }

                // Set as selected model
                settings.selectedModelID = model.id

                // Load the model
                try? await TranscriptionService.shared.loadModel(unifiedID: model.id)

                refreshPermissionStatus()

                withAnimation {
                    currentStep = .permissions
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
    let model: UnifiedModelInfo
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

                        // Provider badge
                        Text(model.provider.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                    }

                    HStack(spacing: 8) {
                        Text(model.sizeDescription)
                        Text("•")
                        if case .englishOnly = model.languageSupport {
                            Text("English only")
                        } else {
                            Text("Multilingual")
                        }
                    }
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
