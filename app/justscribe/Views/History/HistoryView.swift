//
//  HistoryView.swift
//  justscribe
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

struct HistoryView: View {
    let store: HistoryStore
    let playback: HistoryPlayback
    let openSettings: () -> Void
    /// Hides the window and pastes into the app that was in front; returns nil when it pasted, or
    /// a notice saying why it could only copy.
    let paste: (String) -> String?

    /// Read live so the empty state follows the switch while the window stays open.
    @AppStorage(AppSettings.historyKeepsTranscriptionsKey) private var isHistoryOn = false

    @State private var query = ""
    @State private var selection: UUID?
    @State private var notice: String?

    private var shown: [DictationRecord] { store.search(query) }
    private var selected: DictationRecord? { shown.first { $0.id == selection } ?? store.records.first { $0.id == selection } }

    var body: some View {
        HSplitView {
            list
                .frame(minWidth: 260, idealWidth: 300)
            detail
                .frame(minWidth: 320)
        }
        .frame(minWidth: 640, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: selection) { playback.stop(); notice = nil }
    }

    // MARK: - List

    private var list: some View {
        VStack(spacing: 0) {
            TextField("Search", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(12)
            if store.records.isEmpty {
                emptyState(
                    isHistoryOn ? "No dictations yet." : "History is off. Turn on Keep Transcriptions in Settings to start keeping dictations.",
                    showSettings: !isHistoryOn)
            } else if shown.isEmpty {
                emptyState("No matches.", showSettings: false)
            } else {
                List(shown, selection: $selection) { record in
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(HistoryPolicy.rowTime(record.createdAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(HistoryPolicy.rowTitle(record.text))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Spacer(minLength: 4)
                        if record.audioFileName != nil {
                            Image(systemName: "waveform").foregroundStyle(.secondary).font(.caption)
                        }
                        Text(HistoryPolicy.duration(record.durationSeconds))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .tag(record.id)
                }
                .listStyle(.inset)
            }
        }
    }

    private func emptyState(_ text: String, showSettings: Bool) -> some View {
        VStack(spacing: 10) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if showSettings {
                Button("Open Settings", action: openSettings).buttonStyle(.pill)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let record = selected {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView {
                    Text(record.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))

                Text(details(record))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let notice {
                    Text(notice).font(.caption).foregroundStyle(.secondary)
                }

                HStack {
                    Button("Copy") {
                        ClipboardService.shared.copyToClipboard(record.text)
                        notice = "Copied"
                    }
                    .buttonStyle(.pill)
                    Button("Paste") {
                        notice = paste(record.text)
                    }
                    .buttonStyle(.pill)
                    if let url = store.audioURL(for: record) {
                        if playback.playingURL == url {
                            Button("Stop") { playback.stop() }.buttonStyle(.pill)
                        } else {
                            Button("Play") { playback.play(url) }.buttonStyle(.pill)
                        }
                    }
                    Spacer()
                    Button("Delete") {
                        let next = shown.firstIndex { $0.id == record.id }.flatMap { index -> UUID? in
                            let rest = shown.enumerated().filter { $0.offset != index }.map(\.element)
                            return rest.isEmpty ? nil : rest[min(index, rest.count - 1)].id
                        }
                        playback.stop()
                        store.delete(record.id)
                        selection = next
                    }
                    .buttonStyle(.pill)
                }
            }
            .padding(16)
        } else {
            Text(store.records.isEmpty ? "" : "Select a dictation")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func details(_ record: DictationRecord) -> String {
        var parts = [HistoryPolicy.rowTime(record.createdAt), HistoryPolicy.duration(record.durationSeconds)]
        if let model = UnifiedModelInfo.model(forID: record.modelID) { parts.append(model.displayName) }
        if let language = record.language, !language.isEmpty { parts.append(language) }
        return parts.joined(separator: " · ")
    }
}
