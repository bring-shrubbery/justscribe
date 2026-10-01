//
//  MicrophoneSettingsSection.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
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

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct MicrophoneSettingsSection: View {
    @Bindable var settings: AppSettings
    @State private var availableMicrophones: [MicrophoneDevice] = []
    @State private var orderedMicrophones: [MicrophoneDevice] = []
    @State private var draggingID: String?
    @State private var refreshRotation: Double = 0
    @State private var isRefreshAnimating: Bool = false

    var body: some View {
        SettingsSectionContainer(title: "Microphone Priority") {
            Button {
                triggerRefresh()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(refreshRotation), anchor: UnitPoint(x: 0.5, y: 0.58))
                    Text("Refresh")
                }
            }
            .buttonStyle(.pillSmall)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Drag to reorder, or use the arrows. Blocked microphones are never selected — even if they're at the top of the list.")
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
                                isBanned: settings.bannedMicrophoneIDs.contains(mic.id),
                                isBeingDragged: draggingID == mic.id,
                                onMoveUp: { moveMicrophone(mic, direction: .up) },
                                onMoveDown: { moveMicrophone(mic, direction: .down) },
                                onToggleBan: { toggleBan(mic) }
                            )
                            .onDrag {
                                draggingID = mic.id
                                return NSItemProvider(object: mic.id as NSString)
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: MicrophoneDropDelegate(
                                    targetID: mic.id,
                                    orderedMicrophones: $orderedMicrophones,
                                    draggingID: $draggingID,
                                    onCommit: persistOrder
                                )
                            )

                            if mic.id != orderedMicrophones.last?.id {
                                Divider()
                                    .padding(.leading, 28)
                            }
                        }
                    }
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .onAppear {
            refreshMicrophones()
        }
    }

    private func triggerRefresh() {
        refreshMicrophones()
        guard !isRefreshAnimating else { return }
        isRefreshAnimating = true
        withAnimation(.easeInOut(duration: 0.55)) {
            refreshRotation += 360
        } completion: {
            isRefreshAnimating = false
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
        persistOrder()
    }

    private func toggleBan(_ mic: MicrophoneDevice) {
        if let index = settings.bannedMicrophoneIDs.firstIndex(of: mic.id) {
            settings.bannedMicrophoneIDs.remove(at: index)
        } else {
            settings.bannedMicrophoneIDs.append(mic.id)
        }
    }

    private func persistOrder() {
        settings.microphonePriority = orderedMicrophones.map { $0.id }
    }
}

private struct MicrophoneDropDelegate: DropDelegate {
    let targetID: String
    @Binding var orderedMicrophones: [MicrophoneDevice]
    @Binding var draggingID: String?
    let onCommit: () -> Void

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        onCommit()
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let dragID = draggingID,
              dragID != targetID,
              let fromIndex = orderedMicrophones.firstIndex(where: { $0.id == dragID }),
              let toIndex = orderedMicrophones.firstIndex(where: { $0.id == targetID })
        else { return }

        if orderedMicrophones[toIndex].id != dragID {
            withAnimation(.easeInOut(duration: 0.18)) {
                let moved = orderedMicrophones.remove(at: fromIndex)
                orderedMicrophones.insert(moved, at: toIndex)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

struct MicrophoneRow: View {
    let microphone: MicrophoneDevice
    let isFirst: Bool
    let isLast: Bool
    let isBanned: Bool
    let isBeingDragged: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onToggleBan: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 16)
                .onHover { hovering in
                    if hovering {
                        NSCursor.openHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }

            Image(systemName: micIconName)
                .foregroundStyle(micIconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(microphone.name)
                    .font(.body)
                    .strikethrough(isBanned, color: .secondary)

                if isBanned {
                    Text("Blocked")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if !microphone.isAvailable {
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

            Button {
                onToggleBan()
            } label: {
                Image(systemName: isBanned ? "slash.circle.fill" : "slash.circle")
                    .font(.body)
                    .foregroundStyle(isBanned ? Color.red : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(isBanned ? "Allow this microphone" : "Block this microphone")
        }
        .padding(.leading, 0)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .opacity(isBanned ? 0.55 : 1)
        .opacity(isBeingDragged ? 0.3 : 1)
        .animation(.easeInOut(duration: 0.18), value: isBanned)
    }

    private var micIconName: String {
        if isBanned { return "mic.slash.fill" }
        return microphone.isAvailable ? "mic.fill" : "mic.slash"
    }

    private var micIconColor: Color {
        if isBanned { return .secondary }
        return microphone.isAvailable ? Color.accentColor : Color.secondary
    }
}
