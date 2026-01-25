//
//  MicrophoneSettingsSection.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import SwiftUI
import AVFoundation

struct MicrophoneSettingsSection: View {
    @Bindable var settings: AppSettings
    @State private var availableMicrophones: [MicrophoneDevice] = []
    @State private var orderedMicrophones: [MicrophoneDevice] = []

    var body: some View {
        SettingsSectionContainer(title: "Microphone Priority") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Drag to reorder. The first available microphone will be used.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if orderedMicrophones.isEmpty {
                    HStack {
                        Image(systemName: "mic.slash")
                            .foregroundStyle(.secondary)
                        Text("No microphones found")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    VStack(spacing: 0) {
                        ForEach(orderedMicrophones) { mic in
                            MicrophoneRow(
                                microphone: mic,
                                isFirst: mic.id == orderedMicrophones.first?.id,
                                isLast: mic.id == orderedMicrophones.last?.id,
                                onMoveUp: { moveMicrophone(mic, direction: .up) },
                                onMoveDown: { moveMicrophone(mic, direction: .down) }
                            )

                            if mic.id != orderedMicrophones.last?.id {
                                Divider()
                                    .padding(.leading, 40)
                            }
                        }
                    }
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Button {
                    refreshMicrophones()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
        .onAppear {
            refreshMicrophones()
        }
    }

    private func refreshMicrophones() {
        #if os(macOS)
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )

        let devices = discoverySession.devices
        availableMicrophones = devices.enumerated().map { index, device in
            MicrophoneDevice(from: device, priority: index)
        }

        // Order by saved priority, keeping new microphones at the end
        var ordered: [MicrophoneDevice] = []
        for savedId in settings.microphonePriority {
            if let mic = availableMicrophones.first(where: { $0.id == savedId }) {
                ordered.append(mic)
            }
        }

        // Add any new microphones not in saved order
        for mic in availableMicrophones where !ordered.contains(where: { $0.id == mic.id }) {
            ordered.append(mic)
        }

        orderedMicrophones = ordered
        #endif
    }

    private enum MoveDirection {
        case up, down
    }

    private func moveMicrophone(_ mic: MicrophoneDevice, direction: MoveDirection) {
        guard let index = orderedMicrophones.firstIndex(where: { $0.id == mic.id }) else { return }

        let newIndex: Int
        switch direction {
        case .up:
            newIndex = max(0, index - 1)
        case .down:
            newIndex = min(orderedMicrophones.count - 1, index + 1)
        }

        guard newIndex != index else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            orderedMicrophones.remove(at: index)
            orderedMicrophones.insert(mic, at: newIndex)
        }

        // Save new order
        settings.microphonePriority = orderedMicrophones.map { $0.id }
    }
}

struct MicrophoneRow: View {
    let microphone: MicrophoneDevice
    let isFirst: Bool
    let isLast: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: microphone.isAvailable ? "mic.fill" : "mic.slash")
                .foregroundStyle(microphone.isAvailable ? Color.accentColor : Color.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(microphone.name)
                    .font(.body)

                if !microphone.isAvailable {
                    Text("Unavailable")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 4) {
                Button {
                    onMoveUp()
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(isFirst)
                .opacity(isFirst ? 0.3 : 1)

                Button {
                    onMoveDown()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(isLast)
                .opacity(isLast ? 0.3 : 1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
