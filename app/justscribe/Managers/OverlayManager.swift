//
//  OverlayManager.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
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

import DynamicLanding
import Foundation
import SwiftUI

// MARK: - Overlay Content View

/// The expanded card shown in the island, with a close button.
private struct OverlayExpandedView: View {
    let manager: OverlayManager

    var body: some View {
        HStack(spacing: 10) {
            // Icon
            iconView
                .frame(width: 30, height: 30)

            // Title + description
            VStack(alignment: .leading) {
                Text(manager.titleText)
                    .font(.headline)
                    .foregroundStyle(textColor)

                if let desc = manager.descriptionText {
                    Text(desc)
                        .font(.caption2)
                        .foregroundStyle(secondaryTextColor)
                }
            }

            Spacer(minLength: 0)

            // Close / cancel button
            // In a press-mode recording the X stops it, rather than hiding a recording that keeps running.
            Button(action: { if let onTap = manager.onTap { onTap() } else { manager.hide() } }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(secondaryTextColor)
            }
            .buttonStyle(.plain)
        }
        .frame(minWidth: 220)
        .frame(height: 40)
    }

    // The island is black in both styles.
    private var textColor: Color { .white }
    private var secondaryTextColor: Color { .white.opacity(0.5) }

    @ViewBuilder
    private var iconView: some View {
        switch manager.state {
        case .idle:
            Image(systemName: "mic.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(textColor)
                .padding(4)
        case .listening:
            Image(systemName: "mic.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.red)
                .padding(4)
        case .processing:
            IslandSpinnerView()
                .foregroundStyle(textColor)
                .padding(7)
        case .completed, .saved:
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.green)
                .padding(4)
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.red)
                .padding(4)
        }
    }
}

/// Reads the waveform inside a view body, so the bars follow the microphone level without
/// the island being shown again.
private struct ListeningWaveform: View {
    let manager: OverlayManager

    var body: some View {
        IslandWaveformView(bars: manager.waveform.bars)
    }
}

/// The compact island's timer. It reads the seconds itself, so the island is shown once per
/// recording rather than re-shown every second (each re-show replaced its content and re-ran
/// the island's state change).
private struct ListeningTimer: View {
    let manager: OverlayManager

    var body: some View {
        let seconds = manager.recordingSeconds
        Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
            .font(.system(size: 12, weight: .medium).monospacedDigit())
    }
}

// MARK: - OverlayManager

@MainActor
@Observable
final class OverlayManager {
    static let shared = OverlayManager()

    private(set) var isVisible = false
    private(set) var currentStyle: OverlayStyle = .bubble

    private var island: DynamicLanding?
    /// The style `island` was built with; a change needs a new island.
    private var islandStyle: OverlayStyle?
    private var autoHideTask: Task<Void, Never>?
    /// Seconds since the recording started, shown in the compact island.
    private(set) var recordingSeconds = 0
    private var recordingTimer: Task<Void, Never>?
    /// The compact island's waveform, fed from the microphone level while listening.
    private(set) var waveform = WaveformLevels()
    private var levelTask: Task<Void, Never>?
    private static let levelInterval: Duration = .milliseconds(50)

    enum OverlayStyle: String, CaseIterable {
        case bubble
        case notch

        var displayName: String {
            switch self {
            case .bubble: return "Floating Bubble"
            case .notch: return "Notch (Dynamic Island)"
            }
        }
    }

    enum OverlayState: Equatable {
        case idle
        case listening
        case processing
        case completed(copiedToClipboard: Bool)
        /// A long dictation's transcript has been written to Transcripts.
        case saved
        case error(message: String)
    }

    private(set) var state: OverlayState = .idle
    /// Shown under "Listening..." instead of "Speak now" (press mode, the mode's name).
    /// Without one, listening shows the compact island instead of the card.
    var listeningHint: String?
    /// Set while a press-to-toggle recording runs: a click on the overlay stops it.
    var onTap: (() -> Void)?

    private init() {}

    func setStyle(_ style: OverlayStyle) {
        currentStyle = style
    }

    // MARK: - State to text mapping (used by OverlayExpandedView)

    var titleText: String {
        switch state {
        case .idle: return "Ready"
        case .listening: return "Listening..."
        case .processing: return "Processing..."
        case .completed: return "Done"
        case .saved: return "Saved"
        case .error(let message): return message
        }
    }

    var descriptionText: String? {
        switch state {
        case .idle: return "Press shortcut to start"
        case .listening: return listeningHint ?? "Speak now"
        case .processing: return "Transcribing audio"
        case .completed(let copiedToClipboard): return copiedToClipboard ? "Copied to clipboard" : nil
        case .saved: return onTap == nil ? "In Transcripts, from the menu" : "Click to open it in Transcripts"
        case .error: return nil
        }
    }

    // MARK: - Island

    private func currentIsland() -> DynamicLanding {
        if let island, islandStyle == currentStyle { return island }
        Task { [old = island] in await old?.hide() }
        var config = IslandConfiguration()
        config.style = currentStyle == .notch ? .automatic : .pill(cornerRadius: 16)
        config.shadow = .none
        let created = DynamicLanding(configuration: config)
        created.onTap = { [weak self] in self?.onTap?() }
        island = created
        islandStyle = currentStyle
        return created
    }

    /// The expanded card, or the compact waveform-and-timer while listening without a hint.
    private func present() {
        let island = currentIsland()
        isVisible = true
        if case .listening = state, listeningHint == nil {
            Task {
                await island.show(
                    compactLeading: {
                        ListeningWaveform(manager: OverlayManager.shared)
                    },
                    trailing: {
                        ListeningTimer(manager: OverlayManager.shared)
                    })
            }
        } else {
            Task { await island.show(expanded: { OverlayExpandedView(manager: OverlayManager.shared) }) }
        }
    }

    private func stopListeningUpdates() {
        recordingTimer?.cancel()
        recordingTimer = nil
        levelTask?.cancel()
        levelTask = nil
    }

    /// Samples `level` into the waveform until listening ends.
    private func startLevelSampling(level: @escaping () -> Float) {
        levelTask?.cancel()
        waveform = WaveformLevels()
        levelTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.levelInterval)
                guard !Task.isCancelled, let self, self.state == .listening else { return }
                // Assigned whole, so the change is one the waveform view is sure to observe.
                var levels = self.waveform
                levels.push(level: level())
                self.waveform = levels
            }
        }
    }

    // MARK: - Show / Hide

    func show(style: OverlayStyle? = nil) {
        if let style = style {
            currentStyle = style
        }
        present()
    }

    func hide() {
        autoHideTask?.cancel()
        autoHideTask = nil
        stopListeningUpdates()
        isVisible = false
        onTap = nil
        let islandToHide = island
        Task {
            // Keep the last state on screen while the island animates out; the idle text would
            // otherwise flash during the hide. Reset only if nothing was shown in the meantime.
            await islandToHide?.hide()
            if !isVisible {
                state = .idle
                listeningHint = nil
                onHidden?()
            }
        }
    }

    /// Called once the island is off screen and nothing else has been shown meanwhile, so a
    /// recording that was still going on underneath can put its indicator back.
    var onHidden: (() -> Void)?

    // MARK: - Convenience methods

    /// Shows the listening indicator. `startedAt` is when the recording began, for the timer;
    /// `level` is where the waveform reads the microphone's loudness.
    func showListening(
        startedAt: Date = Date(),
        level: @escaping () -> Float = { AudioCaptureService.shared.currentAudioLevel }
    ) {
        // Cancel any pending auto-hide from a previous completed/error state
        autoHideTask?.cancel()
        autoHideTask = nil

        state = .listening
        // Read the user's preferred style from UserDefaults
        // Key matches AppSettings.indicatorStyleKey
        if let styleRaw = UserDefaults.standard.string(forKey: "indicatorStyle"),
           let style = OverlayStyle(rawValue: styleRaw) {
            currentStyle = style
        }

        recordingSeconds = max(0, Int(Date().timeIntervalSince(startedAt)))
        stopListeningUpdates()
        // Only the compact island shows the timer and the waveform; the card (with a hint)
        // has no use for them.
        if listeningHint == nil {
            startLevelSampling(level: level)
            let start = startedAt
            recordingTimer = Task { [weak self] in
                var shown = max(0, Int(Date().timeIntervalSince(start)))
                while !Task.isCancelled {
                    // Wake just after the next whole second since `start`, so each tick lands on
                    // a new value: the display never repeats or skips a second.
                    let elapsed = Date().timeIntervalSince(start)
                    let next = Double(shown + 1)
                    try? await Task.sleep(for: .seconds(max(0, next - elapsed) + 0.01))
                    guard !Task.isCancelled, let self, self.state == .listening else { return }
                    let seconds = Int(Date().timeIntervalSince(start))
                    guard seconds != shown else { continue }
                    shown = seconds
                    self.recordingSeconds = seconds
                }
            }
        }
        present()
    }

    func showProcessing() {
        state = .processing
        stopListeningUpdates()
        present()
    }

    /// Shows "Saved"; with `open`, a click on the indicator calls it, and the indicator stays
    /// a little longer so there is time to click.
    func showSaved(open: (() -> Void)? = nil) {
        state = .saved
        stopListeningUpdates()
        if let open {
            onTap = { [weak self] in
                self?.hide()
                open()
            }
        }
        present()
        autoHideTask?.cancel()
        let seconds = open == nil ? 2.5 : 5.0
        autoHideTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            hide()
        }
    }

    func showCompleted(copiedToClipboard: Bool) {
        state = .completed(copiedToClipboard: copiedToClipboard)
        stopListeningUpdates()
        present()

        // Auto-hide after delay (cancel any previous auto-hide first)
        autoHideTask?.cancel()
        autoHideTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            hide()
        }
    }

    func showError(message: String) {
        state = .error(message: message)
        stopListeningUpdates()
        present()

        // Auto-hide after delay (cancel any previous auto-hide first)
        autoHideTask?.cancel()
        autoHideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            hide()
        }
    }
}
