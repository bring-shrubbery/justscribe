//
//  MicrophoneEngine.swift
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

import AVFoundation
import Synchronization

/// The microphone, kept running for the whole session so a recording starts the
/// moment the keyboard asks: an app in the background may keep recording, but
/// it may not start to. Buffers reach a `TranscriptionRun` only while one is
/// routed; between recordings they are dropped.
///
/// The tap runs on the audio thread, so this type is not on the main actor.
nonisolated final class MicrophoneEngine: @unchecked Sendable {

    private let engine = AVAudioEngine()
    private let run = Mutex<TranscriptionRun?>(nil)
    private let lastLevelReport = Mutex<Date>(.distantPast)
    private let onLevel: @Sendable (Float) -> Void

    /// `onLevel` is called on the audio thread, about 15 times a second, while a run is routed.
    init(onLevel: @escaping @Sendable (Float) -> Void) {
        self.onLevel = onLevel
    }

    var inputFormat: AVAudioFormat { engine.inputNode.outputFormat(forBus: 0) }

    var isRunning: Bool { engine.isRunning }

    func start() throws {
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            self?.receive(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        route(to: nil)
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    func route(to run: TranscriptionRun?) {
        self.run.withLock { $0 = run }
    }

    private func receive(_ buffer: AVAudioPCMBuffer) {
        guard let run = run.withLock({ $0 }) else { return }
        run.append(buffer)

        let now = Date.now
        let due = lastLevelReport.withLock { last in
            guard now.timeIntervalSince(last) > 1.0 / 15 else { return false }
            last = now
            return true
        }
        if due { onLevel(Self.level(of: buffer)) }
    }

    /// The buffer's loudness on a 0...1 scale that suits a meter: RMS in decibels, -50 dB to 0.
    static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        let decibels = 20 * log10(max(rms, 0.000_01))
        return min(max((decibels + 50) / 50, 0), 1)
    }
}
