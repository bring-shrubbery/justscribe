//
//  DiagnosticsSettingsSection.swift
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

/// The last sessions' facts, for a bug report: what was captured, what the model returned, how
/// the session ended. Nothing here leaves the Mac unless the user copies it.
struct DiagnosticsSettingsSection: View {
    private var log: DiagnosticsLog { .shared }
    @State private var copiedNote: String?

    var body: some View {
        SettingsSectionContainer(title: "Diagnostics") {
            VStack(alignment: .leading, spacing: 10) {
                Text("If a dictation comes out wrong or empty, copy this report and send it with your bug report. It lists the last \(DiagnosticsLog.capacity) sessions: microphone and format, how much audio was captured and how loud, what the model returned, and how the session ended.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if log.sessions.isEmpty {
                    Text("No sessions recorded yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(log.sessions.prefix(8).enumerated()), id: \.offset) { _, session in
                                Text(session.line)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                }

                HStack {
                    if let copiedNote {
                        Text(copiedNote).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Clear") { log.clear(); copiedNote = nil }
                        .buttonStyle(.pill)
                        .disabled(log.sessions.isEmpty)
                    Button("Copy Report") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(log.report, forType: .string)
                        copiedNote = "Copied"
                    }
                    .buttonStyle(.pill)
                }
            }
        }
    }
}
