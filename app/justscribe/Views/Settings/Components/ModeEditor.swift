//
//  ModeEditor.swift
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
import UniformTypeIdentifiers

/// The sheet that edits one mode: name, instructions, clean-up switch and the apps it applies to.
struct ModeEditor: View {
    let store: ModeStore
    @State var mode: DictationMode
    var isNew = false
    @Environment(\.dismiss) private var dismiss
    @State private var isPickingRunningApp = false

    init(store: ModeStore, mode: DictationMode, isNew: Bool = false) {
        self.store = store
        self._mode = State(initialValue: mode)
        self.isNew = isNew
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "New Mode" : "Edit Mode").font(.headline)

            TextField("Name", text: $mode.name)
                .textFieldStyle(.roundedBorder)
                .disabled(mode.isDefault)

            Toggle("Clean up text", isOn: $mode.cleanUp)
            Text(mode.cleanUp ? "The clean-up model follows these instructions:" : "Text is inserted as dictated, after voice commands and vocabulary.")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $mode.instructions)
                .font(.body)
                .frame(minHeight: 90)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                .disabled(!mode.cleanUp)
                .opacity(mode.cleanUp ? 1 : 0.5)
            if mode.isDefault {
                Button("Reset to Standard Instructions") { mode.instructions = DictationMode.defaultInstructions }
                    .buttonStyle(.pillSmall)
            }

            if !mode.isDefault {
                Text("Apps").font(.body)
                if mode.appBundleIDs.isEmpty {
                    Text("Add the apps this mode applies to.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(mode.appBundleIDs, id: \.self) { id in
                    HStack {
                        if let icon = Self.icon(forBundleID: id) { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
                        Text(Self.displayName(forBundleID: id))
                        Spacer()
                        Button { mode.appBundleIDs.removeAll { $0 == id } } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Menu("Add Running App") {
                        ForEach(Self.runningApps(), id: \.processIdentifier) { app in
                            Button(app.localizedName ?? app.bundleIdentifier ?? "App") {
                                if let id = app.bundleIdentifier, !mode.appBundleIDs.contains(id) { mode.appBundleIDs.append(id) }
                            }
                        }
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    Button("Other…") { pickApp() }.buttonStyle(.pillSmall)
                }
            }

            HStack {
                if !mode.isDefault && !isNew {
                    Button("Delete Mode", role: .destructive) { store.delete(mode.id); dismiss() }.buttonStyle(.pill)
                }
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.pill)
                Button(isNew ? "Add" : "Save") {
                    if isNew { store.add(mode) } else { store.update(mode) }
                    dismiss()
                }
                .buttonStyle(.pill)
                .disabled(mode.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        if !mode.appBundleIDs.contains(id) { mode.appBundleIDs.append(id) }
    }

    static func runningApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    static func displayName(forBundleID id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func icon(forBundleID id: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}
