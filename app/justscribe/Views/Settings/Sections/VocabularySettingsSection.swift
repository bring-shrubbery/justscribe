//
//  VocabularySettingsSection.swift
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

struct VocabularySettingsSection: View {
    private var store: VocabularyStore { .shared }
    @State private var newText = ""
    @State private var newForms = ""
    @State private var editingID: UUID?
    @State private var editText = ""
    @State private var editForms = ""
    @State private var importNote: String?

    var body: some View {
        SettingsSectionContainer(title: "Vocabulary") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Names and words to spell exactly as you write them. Add how the model tends to hear them to make a match certain.")
                    .font(.caption).foregroundStyle(.secondary)
                if store.fileWasSetAside {
                    Text("A damaged vocabulary file was set aside; the list started again.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    TextField("Text, e.g. SwiftUI", text: $newText).textFieldStyle(.roundedBorder)
                    TextField("Also heard as (comma-separated)", text: $newForms).textFieldStyle(.roundedBorder)
                    Button("Add") { add() }.buttonStyle(.pillSmall)
                        .disabled(newText.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                ForEach(store.entries) { entry in
                    if editingID == entry.id {
                        HStack(spacing: 8) {
                            TextField("Text", text: $editText).textFieldStyle(.roundedBorder)
                            TextField("Also heard as", text: $editForms).textFieldStyle(.roundedBorder)
                            Button("Save") {
                                var e = entry; e.text = editText; e.heardAs = Self.forms(editForms)
                                store.update(e); editingID = nil
                            }
                            .buttonStyle(.pillSmall)
                            .disabled(editText.trimmingCharacters(in: .whitespaces).isEmpty)
                            Button("Cancel") { editingID = nil }.buttonStyle(.pillSmall)
                        }
                    } else {
                        HStack(spacing: 8) {
                            Text(entry.text)
                            if !entry.heardAs.isEmpty {
                                Text("heard as " + entry.heardAs.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Edit") { editingID = entry.id; editText = entry.text; editForms = entry.heardAs.joined(separator: ", ") }
                                .buttonStyle(.pillSmall)
                            Button { store.delete(entry.id) } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }

                Divider()
                HStack {
                    Text(store.entries.count == 1 ? "1 entry" : "\(store.entries.count) entries")
                        .font(.caption).foregroundStyle(.secondary)
                    if let importNote { Text(importNote).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Import from Clipboard") { importFromClipboard() }.buttonStyle(.pill)
                }
            }
        }
    }

    private func add() {
        store.add(text: newText, heardAs: Self.forms(newForms))
        newText = ""; newForms = ""
    }

    private func importFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else { importNote = "Nothing to import"; return }
        let added = store.importLines(text)
        importNote = added == 0 ? "Nothing new to import" : (added == 1 ? "Added 1 entry" : "Added \(added) entries")
    }

    private static func forms(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
