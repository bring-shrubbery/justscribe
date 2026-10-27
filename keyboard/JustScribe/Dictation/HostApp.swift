//
//  HostApp.swift
//  JustScribeKeyboard
//
//  Created by Antoni Silvestrovic on 27/10/2026.
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

import UIKit

/// An app the user can be sent back to after the keyboard opened JustScribe.
struct HostApp: Equatable {
    let name: String
    let url: URL
}

/// Apps that can be reopened by URL scheme, by bundle ID.
///
/// iOS has no public way to open an app by its bundle ID, so returning works only
/// for apps listed here; for any other the user swipes back along the bottom edge.
enum HostAppCatalog {

    static func app(forBundleID bundleID: String) -> HostApp? {
        guard let (name, url) = entries[bundleID.lowercased()], let url = URL(string: url) else { return nil }
        return HostApp(name: name, url: url)
    }

    private static let entries: [String: (String, String)] = [
        "com.apple.mobilesms": ("Messages", "sms:"),
        "com.apple.mobilemail": ("Mail", "message:"),
        "com.apple.mobilenotes": ("Notes", "mobilenotes:"),
        "net.whatsapp.whatsapp": ("WhatsApp", "whatsapp://"),
        "net.whatsapp.whatsappsmb": ("WhatsApp Business", "whatsapp-business://"),
        "ph.telegra.telegraph": ("Telegram", "tg://"),
        "org.whispersystems.signal": ("Signal", "sgnl://"),
        "com.facebook.messenger": ("Messenger", "fb-messenger://"),
        "com.burbn.instagram": ("Instagram", "instagram://"),
        "com.atebits.tweetie2": ("X", "twitter://"),
        "com.hammerandchisel.discord": ("Discord", "discord://"),
        "com.tinyspeck.chatlyio": ("Slack", "slack://"),
        "com.microsoft.skype.teams": ("Teams", "msteams://"),
        "com.google.gmail": ("Gmail", "googlegmail://"),
        "com.microsoft.office.outlook": ("Outlook", "ms-outlook://"),
        "com.google.chrome.ios": ("Chrome", "googlechrome://"),
        "com.linkedin.linkedin": ("LinkedIn", "linkedin://"),
        "com.reddit.reddit": ("Reddit", "reddit://"),
        "notion.id": ("Notion", "notion://"),
        "md.obsidian": ("Obsidian", "obsidian://"),
        "com.culturedcode.thingsiphone": ("Things", "things:///"),
        "com.openai.chat": ("ChatGPT", "chatgpt://"),
    ]
}

/// Learns which app the keyboard was in when it opened JustScribe.
///
/// Since iOS 26.4 a keyboard extension is not told its host app. UIKit in the
/// containing app still receives it, as the remote keyboard's source bundle in
/// `_UIRemoteKeyboards.currentState`, shortly after the keyboard opens the app;
/// other dictation keyboards (Wispr Flow, OpenWhispr) read it the same way.
/// It is not API: every step is checked, and when one is missing this stays
/// inert and the user swipes back instead.
final class HostAppObserver: NSObject {

    static let shared = HostAppObserver()

    private var remoteKeyboards: NSObject?
    private var latest: (bundleID: String, date: Date)?
    private var waiters: [UUID: (since: Date, completion: (String?) -> Void)] = [:]

    /// Starts observing; call at launch, since the value is set once and then cleared.
    func start() {
        guard remoteKeyboards == nil,
              let type = NSClassFromString("_UIRemoteKeyboards") as? NSObject.Type
        else { return }
        let shared = NSSelectorFromString("sharedRemoteKeyboards")
        guard type.responds(to: shared),
              let keyboards = type.perform(shared)?.takeUnretainedValue() as? NSObject,
              keyboards.responds(to: NSSelectorFromString("currentState"))
        else { return }
        remoteKeyboards = keyboards
        keyboards.addObserver(self, forKeyPath: "currentState", options: [.new, .initial], context: nil)
    }

    /// The host seen since `since`, waiting up to `timeout` for it to arrive.
    func host(since: Date, timeout: TimeInterval) async -> String? {
        if let latest, latest.date >= since { return latest.bundleID }
        guard remoteKeyboards != nil else { return nil }
        return await withCheckedContinuation { continuation in
            let id = UUID()
            waiters[id] = (since, { continuation.resume(returning: $0) })
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.waiters.removeValue(forKey: id)?.completion(nil)
            }
        }
    }

    nonisolated override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        let state = change?[.newKey] as? NSObject
        let source = NSSelectorFromString("sourceBundleIdentifier")
        let bundleID = state?.responds(to: source) == true
            ? state?.perform(source)?.takeUnretainedValue() as? String
            : nil
        DispatchQueue.main.async { MainActor.assumeIsolated { HostAppObserver.shared.record(bundleID) } }
    }

    private func record(_ bundleID: String?) {
        guard let bundleID, !bundleID.isEmpty else { return }
        let own = Bundle.main.bundleIdentifier ?? ""
        guard bundleID != own, !bundleID.hasPrefix(own + ".") else { return }
        let now = Date.now
        latest = (bundleID, now)
        for (id, waiter) in waiters where now >= waiter.since {
            waiters.removeValue(forKey: id)
            waiter.completion(bundleID)
        }
    }
}
