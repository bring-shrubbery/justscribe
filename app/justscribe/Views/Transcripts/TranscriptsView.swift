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

    @State private var selection: URL?
    @State private var text = ""
    @State private var notice: String?

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
        .onChange(of: selection) { loadText() }
        .onChange(of: store.transcripts) {
            // The selected file is gone (deleted, or removed in the Finder): show the newest instead.
            if selection != nil, selected == nil { selection = store.transcripts.first?.url }
            if selection == nil { selection = store.transcripts.first?.url }
            loadText()
        }
        .onAppear {
            if selection == nil { selection = store.transcripts.first?.url }
            loadText()
        }
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.rowDate(transcript.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(transcript.title)
                            .lineLimit(1)
                            .truncationMode(.tail)
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
                HStack {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        notice = "Copied"
                    }
                    .buttonStyle(.pill)
                    .disabled(text.isEmpty)
                    Button("Show in Finder") { store.revealInFinder(selected) }
                        .buttonStyle(.pill)
                    Spacer()
                    Button("Move to Trash", role: .destructive) {
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
