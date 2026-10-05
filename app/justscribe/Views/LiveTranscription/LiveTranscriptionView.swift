//
//  LiveTranscriptionView.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 05/10/2026.
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

struct LiveTranscriptionView: View {
    @Bindable var model: LiveTranscriptionModel
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let session = model.session {
                sessionView(session)
            } else {
                startView
            }
        }
        .padding(20)
        .frame(minWidth: 480, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Before recording

    private var startView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Record for as long as you like — a talk, a call, a meeting — and read the transcript as it is written.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                sourceRow(
                    "Microphone", systemImage: "mic.fill",
                    caption: "What you say, from the microphone chosen in Settings.",
                    isOn: $model.useMicrophone)
                Divider().padding(.leading, 48)
                sourceRow(
                    "System audio", systemImage: "speaker.wave.2.fill",
                    caption: "What other apps play, such as the other side of a call. macOS asks for permission the first time.",
                    isOn: $model.useSystemAudio)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            speakerOptions

            if !model.hasModel {
                HStack {
                    Label(LiveTranscriptionSession.Message.noModel, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("Open Settings", action: openSettings).buttonStyle(.pill)
                }
                .font(.callout)
            }

            if let notice = model.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack {
                if model.kinds.isEmpty {
                    Text("Turn on at least one source to start.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.start()
                } label: {
                    Label(model.isStarting ? "Starting…" : "Start Recording", systemImage: "record.circle")
                }
                .buttonStyle(.pill)
                .disabled(!model.canStart)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func sourceRow(_ title: String, systemImage: String, caption: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(isOn.wrappedValue ? Color.accentColor : Color.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.pill)
                .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var speakerOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Identify speakers").font(.body)
                    Text(LiveTranscriptionModel.speakerCaption(kinds: model.kinds))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $model.identifySpeakers)
                    .toggleStyle(.pill)
                    .labelsHidden()
            }
            if model.diarization.downloadProgress != nil {
                ProgressView { Text("Downloading the speaker model…").font(.caption) }
                    .progressViewStyle(.linear)
            }
            if model.identifySpeakers {
                HStack {
                    Text("Speakers").font(.callout)
                    TextField("Detect", text: $model.speakerCountText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    Text(LiveTranscriptionModel.speakerCountHint(for: model.speakerCountText, kinds: model.kinds))
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - While recording, and after

    @ViewBuilder
    private func sessionView(_ session: LiveTranscriptionSession) -> some View {
        HStack(alignment: .firstTextBaseline) {
            status(session)
            Spacer()
            Text(TranscriptBuilder.timestamp(session.elapsed))
                .font(.title3.monospacedDigit())
                .foregroundStyle(session.phase == .recording ? .primary : .secondary)
        }

        TranscriptScrollView(paragraphs: session.paragraphs, isGrowing: session.isRunning)
            .id(ObjectIdentifier(session))

        if let notice = session.notice ?? model.notice {
            Text(notice).font(.caption).foregroundStyle(.secondary)
        }

        HStack {
            if session.phase == .recording {
                Button {
                    model.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.pill)
            } else if session.isRunning {
                ProgressView().controlSize(.small)
            } else {
                Button("New Recording") { model.reset() }.buttonStyle(.pill)
                if session.phase == .failed(LiveTranscriptionSession.Message.noModel) {
                    Button("Open Settings", action: openSettings).buttonStyle(.pill)
                }
            }
            Spacer()
            Button("Copy") { model.copy() }
                .buttonStyle(.pill)
                .disabled(session.paragraphs.isEmpty)
            Button("Save…") { model.save() }
                .buttonStyle(.pill)
                .disabled(session.paragraphs.isEmpty)
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private func status(_ session: LiveTranscriptionSession) -> some View {
        switch LiveTranscriptionModel.status(of: session) {
        case .recording:
            HStack(spacing: 8) {
                RecordingDot()
                Text(recordingText(session))
                    .font(.callout)
                    .lineLimit(1)
            }
        case .working(let text):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(text).font(.callout).lineLimit(1)
            }
        case .ended(let text, let systemImage):
            Label(text, systemImage: systemImage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func recordingText(_ session: LiveTranscriptionSession) -> String {
        var text: String
        switch session.kinds {
        case [.microphone, .systemAudio]: text = "Recording the microphone and system audio"
        case [.systemAudio]: text = "Recording system audio"
        default: text = "Recording the microphone"
        }
        if session.backlog > 1 { text += " · \(session.backlog) pieces waiting for the model" }
        return text
    }
}

/// A red dot that breathes while recording.
private struct RecordingDot: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            Circle()
                .fill(Color.red)
                .frame(width: 9, height: 9)
                .opacity(0.55 + 0.45 * (0.5 + 0.5 * cos(phase * 2 * .pi)))
        }
        .accessibilityLabel("Recording")
    }
}
