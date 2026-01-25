//
//  WaveformVisualizerView.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 25/01/2026.
//

import SwiftUI

struct WaveformVisualizerView: View {
    let audioLevel: Float
    let barCount: Int
    let color: Color

    @State private var barHeights: [CGFloat] = []
    @State private var animationPhase: Double = 0

    init(audioLevel: Float, barCount: Int = 5, color: Color = .red) {
        self.audioLevel = audioLevel
        self.barCount = barCount
        self.color = color
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 3, height: barHeight(for: index))
                    .animation(.easeInOut(duration: 0.1), value: audioLevel)
            }
        }
        .onAppear {
            barHeights = Array(repeating: 4, count: barCount)
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 4
        let maxHeight: CGFloat = 16

        // Create variation between bars based on index
        let phaseOffset = Double(index) * 0.3
        let variation = sin(animationPhase + phaseOffset) * 0.3 + 0.7

        // Scale by audio level
        let level = CGFloat(audioLevel) * variation
        let height = baseHeight + (maxHeight - baseHeight) * level

        return max(baseHeight, min(maxHeight, height))
    }
}

struct AnimatedWaveformView: View {
    @State private var audioLevel: Float = 0
    @State private var timer: Timer?

    private var audioService: AudioCaptureService { AudioCaptureService.shared }

    let color: Color
    let barCount: Int

    init(color: Color = .red, barCount: Int = 5) {
        self.color = color
        self.barCount = barCount
    }

    var body: some View {
        WaveformVisualizerView(audioLevel: audioLevel, barCount: barCount, color: color)
            .onAppear {
                startUpdating()
            }
            .onDisappear {
                stopUpdating()
            }
    }

    private func startUpdating() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            withAnimation(.easeOut(duration: 0.05)) {
                audioLevel = audioService.currentAudioLevel
            }
        }
    }

    private func stopUpdating() {
        timer?.invalidate()
        timer = nil
    }
}

#Preview {
    VStack(spacing: 20) {
        Text("Low")
        WaveformVisualizerView(audioLevel: 0.2)

        Text("Medium")
        WaveformVisualizerView(audioLevel: 0.5)

        Text("High")
        WaveformVisualizerView(audioLevel: 0.9)
    }
    .padding()
}
