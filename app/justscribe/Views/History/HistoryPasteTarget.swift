//
//  HistoryPasteTarget.swift
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

/// Where "Paste" from the History window should put the text: into the app that was in front
/// when the window opened, or, when there is no such app, only onto the clipboard.
nonisolated enum HistoryPasteTarget {
    enum Decision: Equatable { case paste(into: String), copyOnly }

    static func decide(previousApp: String?, ownBundleID: String, isStillRunning: Bool) -> Decision {
        guard let previousApp, previousApp != ownBundleID, isStillRunning else { return .copyOnly }
        return .paste(into: previousApp)
    }
}
