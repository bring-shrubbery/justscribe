//
//  DictationClient.swift
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

import Foundation
import Observation

/// The keyboard's side of dictation: it asks the app to record through the
/// `DictationBridge`, mirrors what the app is doing for the toolbar, and types
/// each finished dictation once.
///
/// The keyboard is torn down and made again whenever the user switches apps,
/// so nothing here is kept: it all comes back from the bridge on `refresh()`.
@MainActor @Observable
final class DictationClient {

    private(set) var phase: DictationPhase = .idle
    private(set) var level: Float = 0
    private(set) var recordingStarted: Date?
    private(set) var notice: String?

    /// The app was opened and the keyboard waits for its recording to show up.
    private(set) var isOpeningApp = false

    @ObservationIgnored private let bridge: DictationBridge?
    @ObservationIgnored private let hasFullAccess: () -> Bool
    @ObservationIgnored private let openURL: (URL) -> Void
    @ObservationIgnored private let textBeforeCursor: () -> String?
    @ObservationIgnored private let insert: (String) -> Void
    @ObservationIgnored private var observer: DarwinNotificationObserver?
    @ObservationIgnored private var levelTimer: Timer?

    init(
        bridge: DictationBridge?,
        hasFullAccess: @escaping () -> Bool,
        openURL: @escaping (URL) -> Void,
        textBeforeCursor: @escaping () -> String?,
        insert: @escaping (String) -> Void
    ) {
        self.bridge = bridge
        self.hasFullAccess = hasFullAccess
        self.openURL = openURL
        self.textBeforeCursor = textBeforeCursor
        self.insert = insert
    }

    func activate() {
        observer = DarwinNotificationObserver(name: DictationBridge.changedNotification) { [weak self] in
            self?.refresh()
        }
        refresh()
    }

    func deactivate() {
        observer = nil
        levelTimer?.invalidate()
        levelTimer = nil
    }

    // MARK: - Actions

    func microphoneTapped() {
        notice = nil
        guard hasFullAccess(), let bridge else {
            notice = "Allow Full Access for JustScribe to dictate."
            openURL(DeepLink.setup)
            return
        }
        if bridge.isSessionLive() {
            bridge.send(.start)
        } else {
            // The keyboard cannot record; the app starts recording when it opens.
            isOpeningApp = true
            openURL(DeepLink.dictate)
        }
    }

    func done() {
        bridge?.send(.stop)
    }

    func cancel() {
        bridge?.send(.cancel)
    }

    // MARK: - State

    func refresh() {
        guard let bridge, hasFullAccess() else { return }
        let live = bridge.isSessionLive()
        phase = live ? bridge.phase : .idle
        recordingStarted = phase == .recording ? bridge.recordingStarted : nil
        if phase != .idle { isOpeningApp = false }
        if let error = bridge.errorMessage, phase == .idle { notice = error }

        if let result = bridge.pendingResult() {
            bridge.markConsumed(result)
            insert(TextSpacing.insertion(of: result.text, after: textBeforeCursor()))
        }
        updateLevelPolling()
    }

    /// The app does not post a notification for every level change, so the
    /// keyboard reads it while a recording is on.
    private func updateLevelPolling() {
        if phase == .recording, levelTimer == nil {
            levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.level = self?.bridge?.level ?? 0 }
            }
        } else if phase != .recording {
            levelTimer?.invalidate()
            levelTimer = nil
            level = 0
        }
    }
}
