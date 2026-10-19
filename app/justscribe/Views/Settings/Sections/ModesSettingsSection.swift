//
//  ModesSettingsSection.swift
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

import SwiftUI

/// The dictation modes: one row per mode with the apps it covers, Edit on each, Add Mode in
/// the title. The editor itself is `ModeEditor`, shown as a sheet.
struct ModesSettingsSection: View {
    private var store: ModeStore { .shared }
    @State private var editing: DictationMode?
    @State private var isAdding = false

    var body: some View {
        SettingsSectionContainer(title: "Modes", accessory: {
            Button("Add Mode…") { isAdding = true }.buttonStyle(.pillSmall)
        }) {
            ForEach(store.modes) { mode in
                HStack(spacing: 12) {
                    Image(systemName: mode.isDefault ? "square.grid.2x2" : "app.badge.checkmark")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode.name)
                        Text(mode.isDefault ? "All other apps" : (mode.appBundleIDs.isEmpty ? "No apps yet" : appNames(mode.appBundleIDs)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !mode.cleanUp { Text("Raw").font(.caption).foregroundStyle(.secondary) }
                    Button("Edit") { editing = mode }.buttonStyle(.pillSmall)
                }
            }
        }

        Section {
            Text("The app in front when you press the shortcut picks the mode; Default covers the rest. A mode holds its own clean-up instructions, or none (\"Raw\"), so the text is inserted as dictated.")
                .font(.caption).foregroundStyle(.secondary)
            if store.fileWasSetAside {
                Text("A damaged modes file was set aside; modes started again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .listRowBackground(Color.clear)
        .sheet(item: $editing) { mode in ModeEditor(store: store, mode: mode) }
        .sheet(isPresented: $isAdding) {
            ModeEditor(store: store, mode: DictationMode(id: UUID(), name: "", instructions: "", cleanUp: true, appBundleIDs: []), isNew: true)
        }
    }

    private func appNames(_ ids: [String]) -> String {
        ids.map { ModeEditor.displayName(forBundleID: $0) }.joined(separator: ", ")
    }
}
