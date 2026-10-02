//
//  FileTranscriptionWindowController.swift
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

/// The Transcribe File window. A plain AppKit window hosting the SwiftUI view: a menu-bar
/// app can open and focus it directly, and it can ask before closing on a running job.
final class FileTranscriptionWindowController: NSObject, NSWindowDelegate {
    static let windowIdentifier = NSUserInterfaceItemIdentifier("fileTranscription")

    private let model: FileTranscriptionModel
    private let openSettings: () -> Void
    private var window: NSWindow?

    init(model: FileTranscriptionModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            window.title = "Transcribe File"
            window.identifier = Self.windowIdentifier
            window.isReleasedWhenClosed = false
            let hostingView = NSHostingView(rootView: FileTranscriptionView(model: model, openSettings: openSettings))
            // Only the minimum comes from the content; the window does not resize to fit it.
            hostingView.sizingOptions = [.minSize]
            window.contentView = hostingView
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("FileTranscriptionWindow")
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.job?.isRunning == true else { return true }
        let alert = NSAlert()
        alert.messageText = "Stop transcribing?"
        alert.informativeText = "The transcript so far will be lost."
        alert.addButton(withTitle: "Stop")
        alert.addButton(withTitle: "Keep Transcribing")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        model.cancel()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        // Nothing is kept: closing the window discards the transcript.
        model.reset()
    }
}
