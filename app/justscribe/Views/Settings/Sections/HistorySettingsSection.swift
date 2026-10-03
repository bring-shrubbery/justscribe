//
//  HistorySettingsSection.swift
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

import AppKit
import SwiftUI

struct HistorySettingsSection: View {
    @Bindable var settings: AppSettings
    private var store: HistoryStore { .shared }
    @State private var isConfirmingDeleteAll = false

    var body: some View {
        SettingsSectionContainer(title: "History") {
            VStack(spacing: 12) {
                ToggleSettingsRow(
                    title: "Keep Transcriptions",
                    subtitle: "Save the text of each dictation so you can find and reuse it later",
                    systemImage: "clock.arrow.circlepath",
                    isOn: $settings.historyKeepsTranscriptions
                )

                Divider()

                ToggleSettingsRow(
                    title: "Keep Audio Recordings",
                    subtitle: "Also save the recording. Oldest recordings are removed once they pass 1 GB (about 45 hours)",
                    systemImage: "waveform",
                    isOn: $settings.historyKeepsAudio
                )
                .disabled(!settings.historyKeepsTranscriptions)
                .opacity(settings.historyKeepsTranscriptions ? 1 : 0.5)

                if !(settings.historyKeepsTranscriptions && settings.historyKeepsAudio) && !store.records.isEmpty {
                    Text("Existing items are kept until you delete them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if store.indexWasSetAside {
                    Text("A damaged history index was set aside; history started again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                HStack {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Show History…") { (NSApp.delegate as? AppDelegate)?.showHistory() }
                        .buttonStyle(.pill)
                        .disabled(store.records.isEmpty)
                    Button("Delete All History…") { isConfirmingDeleteAll = true }
                        .buttonStyle(.pill)
                        .disabled(store.records.isEmpty)
                }
            }
        }
        .alert("Delete all history?", isPresented: $isConfirmingDeleteAll) {
            Button("Delete All", role: .destructive) { store.deleteAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(deleteAllQuestion) This cannot be undone.")
        }
    }

    private var deleteAllQuestion: String {
        let count = store.records.count
        return count == 1
            ? "Delete this dictation and its recording?"
            : "Delete all \(count) dictations and their recordings?"
    }

    private var summary: String {
        let count = store.records.count
        let items = count == 1 ? "1 dictation" : "\(count) dictations"
        let size = ByteCountFormatter.string(fromByteCount: Int64(store.audioBytes), countStyle: .file)
        return store.audioBytes > 0 ? "\(items), \(size) of audio" : items
    }
}
