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

import Foundation
import SwiftUI
import DynamicNotchKit

// MARK: - Overlay Content View

/// Custom expanded content for the DynamicNotch, with a close button.
private struct OverlayExpandedView: View {
    let manager: OverlayManager
    let isNotchStyle: Bool

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
            Button(action: { manager.hide() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(secondaryTextColor)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 40)
    }

    private var textColor: Color {
        isNotchStyle ? .white : .primary
    }

    private var secondaryTextColor: Color {
        isNotchStyle ? .white.opacity(0.5) : .secondary
    }

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
            ProgressView()
                .controlSize(.small)
        case .completed:
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

// MARK: - OverlayManager

@MainActor
@Observable
final class OverlayManager {
    static let shared = OverlayManager()

    private(set) var isVisible = false
    private(set) var currentStyle: OverlayStyle = .bubble

    private var notch: DynamicNotch<OverlayExpandedView, EmptyView, EmptyView>?
    private var autoHideTask: Task<Void, Never>?

    enum OverlayStyle: String, CaseIterable {
        case bubble
        case notch

        var displayName: String {
            switch self {
            case .bubble: return "Floating Bubble"
            case .notch: return "Notch (Dynamic Island)"
            }
        }

        var dynamicNotchStyle: DynamicNotchStyle {
            switch self {
            case .bubble: return .floating
            case .notch: return .notch
            }
        }
    }

    enum OverlayState: Equatable {
        case idle
        case listening
        case processing
        case completed(copiedToClipboard: Bool)
        case error(message: String)
    }

    private(set) var state: OverlayState = .idle

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
        case .error(let message): return message
        }
    }

    var descriptionText: String? {
        switch state {
        case .idle: return "Press shortcut to start"
        case .listening: return "Speak now"
        case .processing: return "Transcribing audio"
        case .completed(let copiedToClipboard): return copiedToClipboard ? "Copied to clipboard" : nil
        case .error: return nil
        }
    }

    // MARK: - Show / Hide

    func show(style: OverlayStyle? = nil) {
        if let style = style {
            currentStyle = style
        }

        let isNotch = currentStyle == .notch
        notch = DynamicNotch(
            style: currentStyle.dynamicNotchStyle
        ) {
            OverlayExpandedView(manager: OverlayManager.shared, isNotchStyle: isNotch)
        }

        Task {
            await notch?.expand()
        }
        isVisible = true
    }

    func hide() {
        autoHideTask?.cancel()
        autoHideTask = nil
        let notchToHide = self.notch
        self.notch = nil
        Task { await notchToHide?.hide() }
        isVisible = false
        state = .idle
    }

    func updateState(_ newState: OverlayState) {
        state = newState
        // The OverlayExpandedView reads `state` reactively via @Observable,
        // so no manual notchInfo property updates are needed.
    }

    // MARK: - Convenience methods

    func showListening() {
        // Cancel any pending auto-hide from a previous completed/error state
        autoHideTask?.cancel()
        autoHideTask = nil

        state = .listening
        // Read the user's preferred style from UserDefaults
        // Key matches AppSettings.indicatorStyleKey
        if let styleRaw = UserDefaults.standard.string(forKey: "indicatorStyle"),
           let style = OverlayStyle(rawValue: styleRaw) {
            currentStyle = style
            print("Using indicator style: \(style.rawValue)")
        } else {
            print("No indicator style in UserDefaults, using default: \(currentStyle.rawValue)")
        }
        show()
    }

    func showProcessing() {
        updateState(.processing)
    }

    func showCompleted(copiedToClipboard: Bool) {
        state = .completed(copiedToClipboard: copiedToClipboard)
        if !isVisible { show() }

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
        if !isVisible { show() }

        // Auto-hide after delay (cancel any previous auto-hide first)
        autoHideTask?.cancel()
        autoHideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            hide()
        }
    }
}
