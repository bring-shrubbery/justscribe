//
//  HistoryWindowController.swift
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
import ApplicationServices
import SwiftUI

/// The History window: an AppKit window hosting the SwiftUI view, like the Transcribe File
/// window. It remembers which app was in front when it opened so "Paste" can go back there.
final class HistoryWindowController: NSObject, NSWindowDelegate {
    static let windowIdentifier = NSUserInterfaceItemIdentifier("history")

    private let store: HistoryStore
    private let playback = HistoryPlayback()
    private let openSettings: () -> Void
    private var window: NSWindow?
    private var previousApp: NSRunningApplication?

    init(store: HistoryStore, openSettings: @escaping () -> Void) {
        self.store = store
        self.openSettings = openSettings
    }

    func show() {
        // Captured before we activate ourselves. Taken fresh on every open so Paste never goes to
        // an app from an earlier open; nil when JustScribe itself is in front.
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : front

        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            window.title = "History"
            window.identifier = Self.windowIdentifier
            window.isReleasedWhenClosed = false
            let view = HistoryView(
                store: store, playback: playback,
                openSettings: openSettings,
                paste: { [weak self] text in
                    guard let self else { return HistoryPasteNotice.noTarget }
                    return self.paste(text)
                })
            let hostingView = NSHostingView(rootView: view)
            hostingView.sizingOptions = [.minSize]
            window.contentView = hostingView
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("HistoryWindow")
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Hides the window, brings the previous app back, and pastes. Returns nil when it pasted,
    /// or a notice saying why it could only copy.
    private func paste(_ text: String) -> String? {
        playback.stop()
        let decision = HistoryPasteTarget.decide(
            previousApp: previousApp?.bundleIdentifier,
            ownBundleID: Bundle.main.bundleIdentifier ?? "",
            isStillRunning: previousApp.map { !$0.isTerminated } ?? false)
        let copyToClipboard = UserDefaults.standard.object(forKey: AppSettings.copyToClipboardKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: AppSettings.copyToClipboardKey)
        switch decision {
        case .copyOnly:
            ClipboardService.shared.copyToClipboard(text)
            return HistoryPasteNotice.noTarget
        case .paste:
            // Without Accessibility the synthetic ⌘V is dropped; copy instead and say so.
            guard AXIsProcessTrusted() else {
                ClipboardService.shared.copyToClipboard(text)
                return HistoryPasteNotice.needsAccessibility
            }
            window?.orderOut(nil)
            previousApp?.activate()
            // Give the other app time to become key before ⌘V lands.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                ClipboardService.shared.paste(text, restorePrevious: !copyToClipboard, restoreDelay: 0.5)
            }
            return nil
        }
    }

    func windowWillClose(_ notification: Notification) {
        playback.stop()
    }
}

/// What the History window says when Paste could only copy.
enum HistoryPasteNotice {
    static let noTarget = "Copied — no other app to paste into"
    static let needsAccessibility = "Copied — Accessibility permission is needed to paste"
}
