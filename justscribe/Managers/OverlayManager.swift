//
//  OverlayManager.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import Foundation
import SwiftUI

// Note: This manager will use DynamicNotchKit once added via SPM.
// For now, this is a placeholder implementation.

@Observable
final class OverlayManager {
    static let shared = OverlayManager()

    private(set) var isVisible = false
    private(set) var currentStyle: OverlayStyle = .bubble

    enum OverlayStyle {
        case bubble
        case notch
    }

    enum OverlayState {
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

        // Will be implemented with DynamicNotchKit
        // switch currentStyle {
        // case .bubble:
        //     DynamicNotch(content: TranscriptionOverlayContent())
        //         .notchStyle(.floating)
        //         .show()
        // case .notch:
        //     DynamicNotch(content: TranscriptionOverlayContent())
        //         .notchStyle(.notch)
        //         .show()
        // }

        isVisible = true
    }

    func hide() {
        // DynamicNotch.hide()
        isVisible = false
        state = .idle
    }

    func updateState(_ newState: OverlayState) {
        state = newState
    }

    // MARK: - Convenience methods

    func showListening() {
        state = .listening
        show()
    }

    func showProcessing() {
        state = .processing
    }

    func showCompleted(text: String) {
        state = .completed(text: text)

        // Auto-hide after delay
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                hide()
            }
        }
    }

    func showError(message: String) {
        state = .error(message: message)

        // Auto-hide after delay
        Task {
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run {
                hide()
            }
        }
    }
}
