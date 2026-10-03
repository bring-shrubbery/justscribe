//
//  ClipboardSnapshotTests.swift
//  justscribeTests
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
import Testing
@testable import justscribe

/// Uses a private named pasteboard, never the system clipboard.
@MainActor
struct ClipboardSnapshotTests {

    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("justscribe-tests-\(UUID().uuidString)"))
    }

    @Test func everyRepresentationOfEveryItemComesBack() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let image = NSPasteboardItem()
        image.setData(Data([1, 2, 3, 4]), forType: .png)
        image.setString("a picture", forType: .string)
        let file = NSPasteboardItem()
        file.setString("file:///tmp/example.txt", forType: .fileURL)
        pasteboard.clearContents()
        pasteboard.writeObjects([image, file])

        let snapshot = ClipboardSnapshot(of: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("dictated text", forType: .string)
        snapshot.restore(to: pasteboard)

        let items = pasteboard.pasteboardItems ?? []
        #expect(items.count == 2)
        #expect(items[0].data(forType: .png) == Data([1, 2, 3, 4]))
        #expect(items[0].string(forType: .string) == "a picture")
        #expect(items[1].string(forType: .fileURL) == "file:///tmp/example.txt")
        #expect(snapshot.isTextOnly == false)
    }

    @Test func anEmptyClipboardRestoresAsEmpty() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let snapshot = ClipboardSnapshot(of: pasteboard)
        pasteboard.setString("dictated text", forType: .string)
        snapshot.restore(to: pasteboard)
        #expect((pasteboard.pasteboardItems ?? []).isEmpty)
        #expect(pasteboard.string(forType: .string) == nil)
    }

    @Test func pastTheSizeCapOnlyTheTextIsKept() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let item = NSPasteboardItem()
        item.setData(Data(repeating: 7, count: 2_000), forType: .png)
        item.setString("caption", forType: .string)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])

        let snapshot = ClipboardSnapshot(of: pasteboard, sizeCap: 1_000)
        #expect(snapshot.isTextOnly)
        pasteboard.clearContents()
        snapshot.restore(to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "caption")
        #expect(pasteboard.data(forType: .png) == nil)
    }

    @Test func dynamicTypesAreNotCopied() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let item = NSPasteboardItem()
        item.setString("plain", forType: .string)
        item.setData(Data([9]), forType: NSPasteboard.PasteboardType("dyn.ah62d4rv4gu8y"))
        pasteboard.clearContents()
        pasteboard.writeObjects([item])

        let snapshot = ClipboardSnapshot(of: pasteboard)
        #expect(snapshot.items.count == 1)
        #expect(snapshot.items[0].keys.contains(.string))
        #expect(!snapshot.items[0].keys.contains { $0.rawValue.hasPrefix("dyn.") })
    }
}
