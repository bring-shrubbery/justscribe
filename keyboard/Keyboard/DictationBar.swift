//
//  DictationBar.swift
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

/// The toolbar while the app records: cancel, the level and time, and done.
struct DictationBar: View {

    let dictation: DictationClient

    var body: some View {
        HStack(spacing: 12) {
            Button(action: dictation.cancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.primary.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .disabled(dictation.phase != .recording)
            .accessibilityLabel("Cancel")

            Spacer(minLength: 0)
            if dictation.phase == .transcribing {
                ProgressView()
                Text("Transcribing…").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Bars(level: dictation.level)
                if let started = dictation.recordingStarted {
                    Text(started, style: .timer)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)

            Button(action: dictation.done) {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.accentColor))
            }
            .buttonStyle(.plain)
            .disabled(dictation.phase != .recording)
            .accessibilityLabel("Done")
        }
        .padding(.horizontal, 6)
    }
}

private struct Bars: View {

    let level: Float

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<7, id: \.self) { index in
                let falloff = 1 - abs(Double(index) - 3) / 4
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 4, height: 6 + 24 * Double(level) * falloff)
            }
        }
        .frame(height: 32)
        .animation(.easeOut(duration: 0.1), value: level)
    }
}
