//
//  TranscriptsSettingsSection.swift
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

/// Settings for the transcripts that Long Dictation and Live Transcription save.
struct TranscriptsSettingsSection: View {
    @AppStorage(LiveTranscriptionModel.keepAudioKey) private var keepAudio = false

    var body: some View {
        SettingsSectionContainer(title: "Transcripts") {
            VStack(spacing: 12) {
                ToggleSettingsRow(
                    title: "Keep Audio Recordings",
                    subtitle: "Save the audio of each Long Dictation and Live Transcription next to its transcript, to play back in Transcripts. About 20 MB an hour",
                    systemImage: "waveform",
                    isOn: $keepAudio
                )
                Divider()
                HStack {
                    Text("Transcripts and their recordings stay on this Mac until you move them to the Trash.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Show Transcripts…") { AppDelegate.shared?.showTranscripts() }
                        .buttonStyle(.pill)
                }
            }
        }
    }
}
