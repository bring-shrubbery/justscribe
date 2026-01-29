//
//  OverlayManager.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import Foundation
import SwiftUI
import DynamicNotchKit

@MainActor
@Observable
final class OverlayManager {
    static let shared = OverlayManager()

    private(set) var isVisible = false
    private(set) var currentStyle: OverlayStyle = .bubble

    private var notchInfo: DynamicNotchInfo?

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
        case completed(text: String)
        case error(message: String)
    }

    private(set) var state: OverlayState = .idle

    private init() {}

    func setStyle(_ style: OverlayStyle) {
        currentStyle = style
    }

    func show(style: OverlayStyle? = nil) {
        if let style = style {
            currentStyle = style
        }

        // Create the notch info
        notchInfo = DynamicNotchInfo(
            icon: iconForState(state),
            title: LocalizedStringKey(titleForState(state)),
            description: descriptionForState(state).map { LocalizedStringKey($0) },
            style: currentStyle.dynamicNotchStyle
        )

        Task {
            await notchInfo?.expand()
        }
        isVisible = true
    }

    func hide() {
        Task {
            await notchInfo?.hide()
            notchInfo = nil
        }
        isVisible = false
        state = .idle
    }

    func updateState(_ newState: OverlayState) {
        state = newState

        // Update the notch content if visible
        if isVisible, let notchInfo = notchInfo {
            withAnimation {
                notchInfo.icon = iconForState(newState)
                notchInfo.title = LocalizedStringKey(titleForState(newState))
                notchInfo.description = descriptionForState(newState).map { LocalizedStringKey($0) }
            }
        }
    }

    // MARK: - State to Content Mapping

    private func iconForState(_ state: OverlayState) -> DynamicNotchInfo.Label? {
        switch state {
        case .idle:
            return .init(systemName: "mic.fill")
        case .listening:
            return .init(systemName: "mic.fill", color: .red)
        case .processing:
            return .init(progress: .constant(-1)) // Indeterminate progress
        case .completed:
            return .init(systemName: "checkmark.circle.fill", color: .green)
        case .error:
            return .init(systemName: "exclamationmark.circle.fill", color: .red)
        }
    }

    private func titleForState(_ state: OverlayState) -> String {
        switch state {
        case .idle:
            return "Ready"
        case .listening:
            return "Listening..."
        case .processing:
            return "Processing..."
        case .completed(let text):
            return text.isEmpty ? "Done" : text
        case .error(let message):
            return message
        }
    }

    private func descriptionForState(_ state: OverlayState) -> String? {
        switch state {
        case .idle:
            return "Press shortcut to start"
        case .listening:
            return "Speak now"
        case .processing:
            return "Transcribing audio"
        case .completed:
            return "Copied to clipboard"
        case .error:
            return nil
        }
    }

    // MARK: - Convenience methods

    func showListening() {
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

    func showCompleted(text: String) {
        updateState(.completed(text: text))

        // Auto-hide after delay
        Task {
            try? await Task.sleep(for: .seconds(2))
            hide()
        }
    }

    func showError(message: String) {
        updateState(.error(message: message))

        // Auto-hide after delay
        Task {
            try? await Task.sleep(for: .seconds(3))
            hide()
        }
    }
}
