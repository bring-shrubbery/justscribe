//
//  JustScribeApp.swift
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

@main
struct JustScribeApp: App {

    @State private var session = DictationSession.shared
    @State private var showsListening = false

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "keyboardLab") {
                KeyboardLabView()
            } else {
                home
            }
            #else
            home
            #endif
        }
    }

    private var home: some View {
        HomeView(session: session)
            .fullScreenCover(isPresented: $showsListening) {
                ListeningView(session: session) { showsListening = false }
            }
            .onOpenURL { url in
                guard url.scheme == DeepLink.scheme else { return }
                if url.host() == DeepLink.dictate.host() {
                    showsListening = true
                    Task { await session.begin(recordNow: true) }
                }
            }
    }
}
