//
//  HomeView.swift
//  JustScribeKeyboard
//
//  Created by Antoni Silvestrovic on 22/10/2026.
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

/// Set-up steps, the dictation session, and a field to try the keyboard in.
struct HomeView: View {

    let session: DictationSession

    @State private var tryText = ""
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    step(1, "Add the keyboard",
                         "Settings → JustScribe → Keyboards → turn on JustScribe.")
                    step(2, "Allow Full Access",
                         "In the same place. The keyboard needs it to hand your voice to this app; nothing leaves the phone.")
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                } header: {
                    Text("Set Up")
                }

                Section {
                    LabeledContent("On-device speech", value: speechLabel)
                    if case .failed = session.speechStatus {
                        Button("Try Again") { Task { await session.prepareSpeech() } }
                    }
                } header: {
                    Text("Speech")
                } footer: {
                    Text("Transcription runs on this iPhone. The first time, iOS downloads the language.")
                }

                Section {
                    LabeledContent("Status", value: sessionLabel)
                    if session.isLive {
                        Button("End Session", role: .destructive) { session.end() }
                    } else {
                        Button("Start Session") { Task { await session.begin(recordNow: false) } }
                    }
                    Stepper("Stays ready for \(session.idleTimeoutMinutes) min",
                            value: Binding(get: { session.idleTimeoutMinutes },
                                           set: { session.idleTimeoutMinutes = $0 }),
                            in: 1...60)
                    if let error = session.errorMessage {
                        Text(error).foregroundStyle(.red)
                    }
                } header: {
                    Text("Dictation Session")
                } footer: {
                    Text("While a session is live the microphone stays open in the background, so the keyboard can record without opening this app. The orange dot shows it.")
                }

                Section {
                    TextField("Switch to the JustScribe keyboard and type or dictate here", text: $tryText, axis: .vertical)
                        .lineLimit(3...8)
                    if let last = session.lastTranscript {
                        LabeledContent("Last dictation", value: last)
                    }
                } header: {
                    Text("Try It")
                }
            }
            .navigationTitle("JustScribe")
            .task { await session.prepareSpeech() }
        }
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var speechLabel: String {
        switch session.speechStatus {
        case .notPrepared: "Not ready"
        case .preparing: "Preparing…"
        case .ready: "Ready"
        case .failed(let message): message
        }
    }

    private var sessionLabel: String {
        guard session.isLive else { return "Off" }
        switch session.phase {
        case .idle: return "Live"
        case .recording: return "Recording"
        case .transcribing: return "Transcribing"
        }
    }
}
