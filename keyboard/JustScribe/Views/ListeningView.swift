//
//  ListeningView.swift
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

/// Shown when the keyboard opened the app to dictate. Recording has already
/// started; the user goes back to the app they were typing in, where the
/// keyboard shows the recording and its Done button.
struct ListeningView: View {

    let session: DictationSession
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            LevelMeter(level: session.level, isActive: session.phase == .recording)
                .frame(height: 64)

            VStack(spacing: 10) {
                Text(title)
                    .font(.title.bold())
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            if let error = session.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 12) {
                if session.phase == .recording {
                    Button {
                        Task { await session.stopRecording() }
                    } label: {
                        Text("Stop Here").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                Button("Close", action: dismiss)
                    .controlSize(.large)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    private var title: String {
        switch session.phase {
        case .recording: "Listening"
        case .transcribing: "Transcribing…"
        case .idle: session.isLive ? "Ready" : "Starting…"
        }
    }

    private var message: String {
        switch session.phase {
        case .recording:
            "Go back to the app you were typing in: tap ◀ at the top left. Keep talking, then tap Done on the keyboard."
        case .transcribing:
            "The text will appear in the app you were typing in."
        case .idle:
            "Tap the microphone on the JustScribe keyboard to dictate. It stays ready for \(session.idleTimeoutMinutes) minutes."
        }
    }
}

struct LevelMeter: View {

    let level: Float
    let isActive: Bool

    private let bars = 9

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<bars, id: \.self) { index in
                Capsule()
                    .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.4))
                    .frame(width: 6, height: height(for: index))
            }
        }
        .animation(.easeOut(duration: 0.12), value: level)
    }

    private func height(for index: Int) -> CGFloat {
        let center = Double(bars - 1) / 2
        let falloff = 1 - abs(Double(index) - center) / (center + 1)
        let value = isActive ? Double(level) : 0
        return 8 + 56 * value * falloff
    }
}
