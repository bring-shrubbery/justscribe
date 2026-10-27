//
//  KeyboardLabView.swift
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

#if DEBUG
import SwiftUI

/// A bare text field with the keyboard up, for screenshots of the keyboard in the
/// simulator: launch with `-keyboardLab YES`. Debug builds only.
struct KeyboardLabView: View {

    @State private var text = UserDefaults.standard.string(forKey: "keyboardLabText") ?? ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading) {
            TextField("Message", text: $text, axis: .vertical)
                .focused($isFocused)
                .accessibilityIdentifier("lab-field")
                .padding(12)
                .background(.quaternary, in: .rect(cornerRadius: 18))
            Spacer()
        }
        .padding()
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            isFocused = true
        }
    }
}
#endif
