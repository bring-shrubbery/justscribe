//
//  UpdateService.swift
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

import Foundation
import Sparkle

/// The in-app updater. One Sparkle controller for the app's lifetime: it reads the feed named
/// by `SUFeedURL` in Info.plist on launch and then daily, shows its own dialogs, and installs
/// in the background unless the user turns that off. The rest of the app never sees Sparkle.
@MainActor
@Observable
final class UpdateService {
    static let shared = UpdateService()

    /// False while a check or an install is under way; "Check for Updates…" is disabled then.
    private(set) var canCheckForUpdates = false

    /// Download and install new versions without asking. Sparkle persists the choice itself
    /// (it is not an `AppSettings` field); the default comes from `SUAutomaticallyUpdate`.
    var automaticallyInstallsUpdates: Bool {
        didSet {
            guard automaticallyInstallsUpdates != oldValue else { return }
            controller.updater.automaticallyDownloadsUpdates = automaticallyInstallsUpdates
        }
    }

    private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: NSKeyValueObservation?

    /// A real updater must not run inside the unit-test host or an Xcode preview: it would
    /// hit the network and could put up Sparkle's alert.
    nonisolated static func shouldStartUpdater(environment: [String: String]) -> Bool {
        environment["XCTestConfigurationFilePath"] == nil
            && environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1"
    }

    private init() {
        let start = Self.shouldStartUpdater(environment: ProcessInfo.processInfo.environment)
        controller = SPUStandardUpdaterController(startingUpdater: start, updaterDelegate: nil, userDriverDelegate: nil)
        automaticallyInstallsUpdates = controller.updater.automaticallyDownloadsUpdates
        canCheckForUpdates = controller.updater.canCheckForUpdates
        // Sparkle drives its updater on the main thread, so the change lands on the main actor.
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, change in
            MainActor.assumeIsolated {
                self?.canCheckForUpdates = change.newValue ?? false
            }
        }
    }

    /// Sparkle reports the outcome itself, including "You're up to date".
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
