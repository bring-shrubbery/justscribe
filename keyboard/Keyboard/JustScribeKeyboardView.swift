//
//  JustScribeKeyboardView.swift
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

import KeyboardCore
import SwiftUI

/// The standard keys with JustScribe's toolbar: suggestions and a microphone,
/// or the recording bar while the app records.
struct JustScribeKeyboardView: View {

    let state: Keyboard.State
    let services: Keyboard.Services
    let dictation: DictationClient

    /// Observed so the body, and with it the layout, is rebuilt when the case or
    /// keyboard type changes: KeyboardView takes its layout once, when it is made.
    @EnvironmentObject private var keyboardContext: KeyboardContext

    var body: some View {
        KeyboardView(
            layout: services.layoutService.keyboardLayout(for: keyboardContext),
            state: state,
            services: services,
            buttonContent: { params in
                // The system keyboard's space bar is blank.
                if params.item.action == .space {
                    Color.clear
                } else {
                    params.view
                }
            },
            buttonView: { $0.view },
            collapsedView: { $0.view },
            emojiKeyboard: { _ in
                EmojiKeyboard(actionHandler: services.actionHandler)
            },
            toolbar: { params in
                Toolbar(dictation: dictation, suggestions: params.view)
            }
        )
    }
}

private struct Toolbar<Suggestions: View>: View {

    let dictation: DictationClient
    let suggestions: Suggestions

    var body: some View {
        Group {
            switch dictation.phase {
            case .recording, .transcribing:
                DictationBar(dictation: dictation)
            case .idle:
                HStack(spacing: 4) {
                    if let notice = dictation.notice {
                        Text(notice)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 12)
                    } else if dictation.isOpeningApp {
                        Text("Opening JustScribe…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 12)
                    } else {
                        suggestions.frame(maxWidth: .infinity)
                    }
                    MicrophoneButton(action: dictation.microphoneTapped)
                }
            }
        }
        .frame(height: 48)
    }
}

private struct MicrophoneButton: View {

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "mic.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.accentColor))
                .contentShape(.rect)
                .frame(width: 48, height: 44)
        }
        .buttonStyle(.plain)
        // Clear of the keyboard's rounded top corner.
        .padding(.trailing, 8)
        .accessibilityLabel("Dictate")
    }
}
