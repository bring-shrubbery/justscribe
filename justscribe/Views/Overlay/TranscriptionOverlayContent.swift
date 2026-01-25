//
//  TranscriptionOverlayContent.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import SwiftUI

struct TranscriptionOverlayContent: View {
    let state: OverlayManager.OverlayState

    init(state: OverlayManager.OverlayState = .idle) {
        self.state = state
    }

    var body: some View {
        HStack(spacing: 12) {
            stateIcon
                .font(.title2)
                .frame(width: 28)

            stateContent
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch state {
        case .idle:
            Image(systemName: "mic.fill")
                .foregroundStyle(.secondary)

        case .listening:
            WaveformIndicator()
                .foregroundStyle(.red)

        case .processing:
            ProgressView()
                .scaleEffect(0.8)

        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch state {
        case .idle:
            Text("Ready")
                .foregroundStyle(.secondary)

        case .listening:
            Text("Listening...")
                .foregroundStyle(.primary)

        case .processing:
            Text("Processing...")
                .foregroundStyle(.primary)

        case .completed(let text):
            Text(text)
                .lineLimit(2)
                .foregroundStyle(.primary)

        case .error(let message):
            Text(message)
                .lineLimit(2)
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Waveform Indicator

struct WaveformIndicator: View {
    @State private var animationPhase: Double = 0

    private let barCount = 5

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .frame(width: 3, height: barHeight(for: index))
                    .animation(
                        .easeInOut(duration: 0.4)
                        .repeatForever()
                        .delay(Double(index) * 0.1),
                        value: animationPhase
                    )
            }
        }
        .onAppear {
            animationPhase = 1
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 8
        let maxHeight: CGFloat = 20
        let phase = sin(animationPhase * .pi + Double(index) * 0.5)
        return baseHeight + CGFloat(phase) * (maxHeight - baseHeight) / 2
    }
}

// MARK: - Preview

#Preview("Listening") {
    TranscriptionOverlayContent(state: .listening)
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
}

#Preview("Processing") {
    TranscriptionOverlayContent(state: .processing)
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
}

#Preview("Completed") {
    TranscriptionOverlayContent(state: .completed(text: "Hello, this is a test transcription."))
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
}

#Preview("Error") {
    TranscriptionOverlayContent(state: .error(message: "Microphone not available"))
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
}
