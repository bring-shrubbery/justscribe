//
//  LiveTranscriptionWindowController.swift
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

/// The Live Transcription window. A plain AppKit window hosting the SwiftUI view: a menu-bar
/// app can open and focus it directly, and it can ask before closing on a running session.
final class LiveTranscriptionWindowController: NSObject, NSWindowDelegate {
    static let windowIdentifier = NSUserInterfaceItemIdentifier("liveTranscription")

    private let model: LiveTranscriptionModel
    private let openSettings: () -> Void
    private var window: NSWindow?

    init(model: LiveTranscriptionModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
    }

    /// Whether a recording or its last steps are under way; closing the window would end them.
    var isRunning: Bool { model.session?.isRunning == true }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            window.title = "Live Transcription"
            window.identifier = Self.windowIdentifier
            window.isReleasedWhenClosed = false
            let hostingView = NSHostingView(rootView: LiveTranscriptionView(model: model, openSettings: openSettings))
            // Only the minimum comes from the content; the window does not resize to fit it.
            hostingView.sizingOptions = [.minSize]
            window.contentView = hostingView
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("LiveTranscriptionWindow")
            self.window = window
        }
        model.prepareSpeakerModelsIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard isRunning else { return true }
        let alert = NSAlert()
        alert.messageText = "Stop recording?"
        alert.informativeText = "The recording ends and the transcript so far is lost."
        alert.addButton(withTitle: "Stop")
        alert.addButton(withTitle: "Keep Recording")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        // A session that ended while the alert was up has a final transcript the alert did
        // not mean; keep the window open with it.
        return isRunning
    }

    func windowWillClose(_ notification: Notification) {
        // Nothing is kept: closing the window discards the transcript, and ends a session the
        // user agreed to stop.
        model.discard()
    }
}
