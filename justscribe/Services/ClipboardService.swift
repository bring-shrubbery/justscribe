//
//  ClipboardService.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import Foundation
import AppKit

final class ClipboardService {
    static let shared = ClipboardService()

    private init() {}

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func pasteFromClipboard() -> String? {
        return NSPasteboard.general.string(forType: .string)
    }
}
