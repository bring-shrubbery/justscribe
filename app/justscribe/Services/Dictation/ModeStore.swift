//
//  ModeStore.swift
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
import Observation

/// The dictation modes, Default first, in `modes.json`.
@Observable
final class ModeStore {
    static let shared = ModeStore(fileURL: JSONFile.containerURL("modes.json"))

    private(set) var modes: [DictationMode] = []
    private(set) var fileWasSetAside = false
    private let fileURL: URL

    init(fileURL: URL) { self.fileURL = fileURL }

    func load() {
        switch JSONFile.read(ModesFile.self, from: fileURL) {
        case .missing: modes = []
        case .loaded(let file): modes = file.modes
        case .damaged: JSONFile.setAside(fileURL); fileWasSetAside = true; modes = []
        }
        ensureDefault()
    }

    func add(_ mode: DictationMode) {
        var mode = mode
        mode.appBundleIDs = Array(Set(mode.appBundleIDs)).sorted()
        releaseApps(mode.appBundleIDs, except: mode.id)
        modes.append(mode)
        ensureDefault()
        save()
    }

    func update(_ mode: DictationMode) {
        guard let index = modes.firstIndex(where: { $0.id == mode.id }) else { return }
        var mode = mode
        if mode.isDefault { mode.appBundleIDs = []; mode.name = "Default" }
        releaseApps(mode.appBundleIDs, except: mode.id)
        modes[index] = mode
        save()
    }

    func delete(_ id: UUID) {
        guard id != DictationMode.defaultID else { return }
        modes.removeAll { $0.id == id }
        save()
    }

    /// The mode listing the app, else Default.
    func mode(forApp bundleID: String?) -> DictationMode {
        if let bundleID, let mode = modes.first(where: { $0.appBundleIDs.contains(bundleID) }) { return mode }
        return modes.first { $0.isDefault } ?? DictationMode.makeDefault()
    }

    /// Moves an app to one mode; it leaves whichever mode listed it before.
    func assign(app bundleID: String, to modeID: UUID) {
        guard let index = modes.firstIndex(where: { $0.id == modeID }), modeID != DictationMode.defaultID else { return }
        releaseApps([bundleID], except: modeID)
        if !modes[index].appBundleIDs.contains(bundleID) { modes[index].appBundleIDs.append(bundleID) }
        save()
    }

    private func releaseApps(_ apps: [String], except modeID: UUID) {
        for i in modes.indices where modes[i].id != modeID {
            modes[i].appBundleIDs.removeAll { apps.contains($0) }
        }
    }

    private func ensureDefault() {
        if let index = modes.firstIndex(where: { $0.isDefault }) {
            if index != 0 { modes.insert(modes.remove(at: index), at: 0) }
        } else {
            modes.insert(DictationMode.makeDefault(), at: 0)
            save()
        }
    }

    private func save() {
        JSONFile.write(ModesFile(version: ModesFile.currentVersion, modes: modes), to: fileURL)
    }
}
