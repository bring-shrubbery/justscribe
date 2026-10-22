//
//  DictationBridge.swift
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

/// The App Group the app and the keyboard share. The keyboard reaches it only
/// with Full Access, which is why the keyboard asks for it.
nonisolated enum AppGroup {

    static let id = "group.com.quassum.justscribe"

    static var defaults: UserDefaults? { UserDefaults(suiteName: id) }
}

/// What the app's dictation session is doing, as the keyboard sees it.
nonisolated enum DictationPhase: String, Codable, Sendable {
    /// No recording: the session may still be live, waiting for the next one.
    case idle
    case recording
    case transcribing
}

/// What the keyboard asks the app to do. Each is a Darwin notification, which
/// carries no payload: anything more goes through the shared defaults.
nonisolated enum DictationCommand: String, CaseIterable, Sendable {
    case start
    case stop
    case cancel

    var notificationName: String { "com.quassum.justscribe.dictation.\(rawValue)" }
}

/// A finished dictation, written by the app for the keyboard to insert once.
nonisolated struct DictationResult: Codable, Equatable, Sendable {
    let id: UUID
    let text: String
    let date: Date
}

/// The keyboard extension cannot record: iOS gives keyboards no microphone.
/// The app records instead, kept alive in the background by its audio session,
/// and the two talk through here: the keyboard sends commands as Darwin
/// notifications, the app answers through the App Group's defaults and posts
/// `changedNotification` whenever it writes.
nonisolated final class DictationBridge: @unchecked Sendable {

    static let changedNotification = "com.quassum.justscribe.dictation.changed"

    /// How long a heartbeat counts: the app writes one every second while its
    /// session is live, so an older one means the app was suspended or quit.
    static let heartbeatValidity: TimeInterval = 3

    /// A result older than this is never inserted, so a keyboard that opens in
    /// another text field much later does not type an old dictation into it.
    static let resultValidity: TimeInterval = 120

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    convenience init?() {
        guard let defaults = AppGroup.defaults else { return nil }
        self.init(defaults: defaults)
    }

    private enum Key {
        static let phase = "dictation.phase"
        static let heartbeat = "dictation.heartbeat"
        static let level = "dictation.level"
        static let recordingStarted = "dictation.recordingStarted"
        static let result = "dictation.result"
        static let consumedResult = "dictation.consumedResult"
        static let error = "dictation.error"
    }

    // MARK: - Read by the keyboard

    var phase: DictationPhase {
        defaults.string(forKey: Key.phase).flatMap(DictationPhase.init) ?? .idle
    }

    var heartbeat: Date? {
        let interval = defaults.double(forKey: Key.heartbeat)
        return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
    }

    /// Whether the app is running a session that can record right away.
    func isSessionLive(now: Date = .now) -> Bool {
        guard let heartbeat else { return false }
        return now.timeIntervalSince(heartbeat) < Self.heartbeatValidity
    }

    /// The microphone level, 0...1, while recording.
    var level: Float { defaults.float(forKey: Key.level) }

    var recordingStarted: Date? {
        let interval = defaults.double(forKey: Key.recordingStarted)
        return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
    }

    /// The last error the app reported, shown in the keyboard until the next recording.
    var errorMessage: String? { defaults.string(forKey: Key.error) }

    /// The result to insert, if there is one the keyboard has not inserted yet.
    func pendingResult(now: Date = .now) -> DictationResult? {
        guard let data = defaults.data(forKey: Key.result),
              let result = try? JSONDecoder().decode(DictationResult.self, from: data)
        else { return nil }
        guard result.id.uuidString != defaults.string(forKey: Key.consumedResult) else { return nil }
        guard now.timeIntervalSince(result.date) < Self.resultValidity else { return nil }
        return result
    }

    func markConsumed(_ result: DictationResult) {
        defaults.set(result.id.uuidString, forKey: Key.consumedResult)
    }

    func send(_ command: DictationCommand) {
        Self.post(command.notificationName)
    }

    // MARK: - Written by the app

    func publish(phase: DictationPhase) {
        defaults.set(phase.rawValue, forKey: Key.phase)
        if phase == .recording {
            defaults.set(Date.now.timeIntervalSince1970, forKey: Key.recordingStarted)
            defaults.removeObject(forKey: Key.error)
        }
        if phase != .recording { defaults.set(Float(0), forKey: Key.level) }
        Self.post(Self.changedNotification)
    }

    func publishHeartbeat(_ date: Date? = .now) {
        defaults.set(date?.timeIntervalSince1970 ?? 0, forKey: Key.heartbeat)
        if date == nil { Self.post(Self.changedNotification) }
    }

    /// Written many times a second; posts nothing, the keyboard polls it while recording.
    func publish(level: Float) {
        defaults.set(level, forKey: Key.level)
    }

    func publish(result text: String) {
        let result = DictationResult(id: UUID(), text: text, date: .now)
        if let data = try? JSONEncoder().encode(result) {
            defaults.set(data, forKey: Key.result)
        }
        Self.post(Self.changedNotification)
    }

    func publish(error message: String) {
        defaults.set(message, forKey: Key.error)
        Self.post(Self.changedNotification)
    }

    private static func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString),
            nil, nil, true
        )
    }
}

/// Calls a handler on the main actor whenever a Darwin notification is posted,
/// by this process or another, until it is released.
nonisolated final class DarwinNotificationObserver: @unchecked Sendable {

    private let name: String
    private let handler: @MainActor () -> Void

    init(name: String, handler: @escaping @MainActor () -> Void) {
        self.name = name
        self.handler = handler
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let me = Unmanaged<DarwinNotificationObserver>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { MainActor.assumeIsolated { me.handler() } }
            },
            name as CFString,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(name as CFString),
            nil
        )
    }
}

nonisolated enum DeepLink {

    static let scheme = "justscribe"

    /// Opens the app and starts recording at once.
    static let dictate = URL(string: "\(scheme)://dictate")!

    /// Opens the app on its set-up steps.
    static let setup = URL(string: "\(scheme)://setup")!
}
