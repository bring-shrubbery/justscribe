//
//  TranscriptsView.swift
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

struct TranscriptsView: View {
    let store: TranscriptStore
    let playback: HistoryPlayback
    let retranscription: RetranscriptionModel
    /// Opens Settings on the model download sheet.
    let openModelDownload: () -> Void

    @State private var selection: URL?
    @State private var text = ""
    @State private var notice: String?
    @State private var isChoosingModel = false

    private var selected: SavedTranscript? { store.transcripts.first { $0.url == selection } }

    var body: some View {
        HSplitView {
            list
                .frame(minWidth: 260, idealWidth: 300)
            detail
                .frame(minWidth: 340)
        }
        .frame(minWidth: 680, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: selection) {
            playback.stop()
            loadText()
        }
        .onChange(of: store.transcripts) {
            // The selected file is gone (deleted, or removed in the Finder): show the newest instead.
            takeRequestedSelection()
            if selection != nil, selected == nil { selection = store.transcripts.first?.url }
            if selection == nil { selection = store.transcripts.first?.url }
            loadText()
        }
        .onAppear {
            takeRequestedSelection()
            if selection == nil { selection = store.transcripts.first?.url }
            loadText()
        }
        .onChange(of: store.requestedSelection) { takeRequestedSelection() }
    }

    /// Selects the transcript something asked the window to show, once it is in the list.
    private func takeRequestedSelection() {
        guard let requested = store.requestedSelection,
              store.transcripts.contains(where: { $0.url == requested }) else { return }
        selection = requested
        store.requestedSelection = nil
    }

    // MARK: - List

    private var list: some View {
        VStack(spacing: 0) {
            if store.transcripts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text("No transcripts yet.\nLong dictations, live transcriptions and transcribed files are saved here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.transcripts, selection: $selection) { transcript in
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.rowDate(transcript.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(transcript.title)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Spacer(minLength: 4)
                        if transcript.audioURL != nil {
                            Image(systemName: "waveform").foregroundStyle(.secondary).font(.caption)
                        }
                    }
                    .padding(.vertical, 2)
                    .tag(transcript.url)
                }
                .listStyle(.inset)
            }
            Divider()
            HStack {
                Button {
                    store.openFolder()
                } label: {
                    Label("Open Folder", systemImage: "folder")
                }
                .buttonStyle(.pillSmall)
                Spacer()
                Button {
                    store.load()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.pillSmall)
                .help("Refresh")
            }
            .padding(10)
        }
    }

    /// "Today, 14:32", "Yesterday, 09:10", "3 Oct 2026, 18:05".
    nonisolated static func rowDate(_ date: Date, now: Date = Date()) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Today, \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday, \(time)"
        }
        return "\(date.formatted(date: .abbreviated, time: .omitted)), \(time)"
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let selected {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selected.title).font(.headline)
                    Text(selected.date.formatted(date: .long, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ScrollView {
                    Text(text)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                if let notice {
                    Text(notice).font(.caption).foregroundStyle(.secondary)
                }
                if retranscription.transcript?.url == selected.url, let status = retranscription.status {
                    retranscriptionStatus(status)
                } else if retranscription.noticeURL == selected.url, let notice = retranscription.notice {
                    Label(notice, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        notice = "Copied"
                    }
                    .buttonStyle(.pill)
                    .disabled(text.isEmpty)
                    if let audio = selected.audioURL {
                        if playback.playingURL == audio {
                            Button("Stop") { playback.stop() }.buttonStyle(.pill)
                        } else {
                            Button("Play") { playback.play(audio) }.buttonStyle(.pill)
                        }
                        Button("Transcribe Again…") { isChoosingModel = true }
                            .buttonStyle(.pill)
                            .disabled(retranscription.isRunning)
                            .help("Transcribe this recording again with another model")
                            .popover(isPresented: $isChoosingModel, arrowEdge: .bottom) {
                                RetranscriptionOptions(
                                    model: retranscription,
                                    start: { chosen, speakers in
                                        isChoosingModel = false
                                        retranscription.start(selected, model: chosen, speakers: speakers)
                                    },
                                    moreModels: {
                                        isChoosingModel = false
                                        openModelDownload()
                                    })
                            }
                    }
                    Button("Show in Finder") { store.revealInFinder(selected) }
                        .buttonStyle(.pill)
                    Spacer()
                    Button("Move to Trash", role: .destructive) {
                        playback.stop()
                        do {
                            try store.delete(selected)
                        } catch {
                            notice = "Couldn't delete the transcript: \(error.localizedDescription)"
                        }
                    }
                    .buttonStyle(.pill)
                }
            }
            .padding(20)
        } else {
            Text("Select a transcript to read it.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The run's progress, with a way to stop it.
    @ViewBuilder
    private func retranscriptionStatus(_ status: FileTranscriptionModel.Status) -> some View {
        HStack(spacing: 12) {
            switch status {
            case .working(let text, let progress?):
                ProgressView(value: progress) { Text(text).font(.caption).lineLimit(1) }
            case .working(let text, nil):
                ProgressView { Text(text).font(.caption).lineLimit(1) }
                    .progressViewStyle(.linear)
            case .ended(let text, let systemImage):
                Label(text, systemImage: systemImage).font(.caption).foregroundStyle(.secondary)
            }
            Button("Cancel") { retranscription.cancel() }
                .buttonStyle(.pillSmall)
                .disabled(retranscription.job?.isCancelling == true)
        }
    }

    private func loadText() {
        notice = nil
        guard let selected else {
            text = ""
            return
        }
        do {
            text = try store.text(of: selected)
        } catch {
            text = ""
            notice = "Couldn't read the transcript: \(error.localizedDescription)"
        }
    }
}

/// The choices for transcribing a recording again: which model, and whether to label speakers.
private struct RetranscriptionOptions: View {
    @Bindable var model: RetranscriptionModel
    let start: (UnifiedModelInfo, SpeakerRequest) -> Void
    /// Opens Settings on the model download sheet.
    let moreModels: () -> Void

    @State private var modelID = ""

    private var models: [UnifiedModelInfo] { model.models }
    private var chosen: UnifiedModelInfo? { models.first { $0.id == modelID } ?? models.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transcribe this recording again")
                .font(.headline)
            if models.isEmpty {
                Text("No models downloaded")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Model", selection: $modelID) {
                    ForEach(models) { Text($0.fullDisplayName).tag($0.id) }
                }
            }
            Toggle("Identify speakers", isOn: $model.identifySpeakers)
            if model.identifySpeakers {
                HStack {
                    Text("Speakers")
                    TextField("Detect", text: $model.speakerCountText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    Text(FileTranscriptionModel.speakerCountHint(for: model.speakerCountText))
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Text("The new transcript is saved next to this one; the model you use for dictation is loaded back afterwards.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(action: moreModels) {
                    Label("More Models", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.pill)
                Spacer()
                Button("Transcribe") {
                    guard let chosen else { return }
                    start(chosen, model.speakerRequest)
                }
                .buttonStyle(.pill)
                .keyboardShortcut(.defaultAction)
                .disabled(chosen == nil)
            }
        }
        .padding(16)
        .frame(width: 340)
        .onAppear {
            // The model loaded now first, then the first on disk.
            if let loaded = model.loadedModelID(), models.contains(where: { $0.id == loaded }) {
                modelID = loaded
            } else {
                modelID = models.first?.id ?? ""
            }
        }
    }
}
