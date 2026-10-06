//
//  TranscriptsWindowController.swift
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

import AppKit
import SwiftUI

/// The Transcripts window: every saved transcript, newest first, with its text alongside.
final class TranscriptsWindowController: NSObject, NSWindowDelegate {
    static let windowIdentifier = NSUserInterfaceItemIdentifier("transcripts")

    private let store: TranscriptStore
    private var window: NSWindow?

    init(store: TranscriptStore) {
        self.store = store
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            window.title = "Transcripts"
            window.identifier = Self.windowIdentifier
            window.isReleasedWhenClosed = false
            let hostingView = NSHostingView(rootView: TranscriptsView(store: store))
            hostingView.sizingOptions = [.minSize]
            window.contentView = hostingView
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("TranscriptsWindow")
            self.window = window
        }
        store.load()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
