//
//  SpeakerDiarizationService.swift
//  justscribe
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

import FluidAudio
import Foundation
import Observation

/// Says who spoke when in a file, with FluidAudio's offline diarizer. Its models (about
/// 22 MB) are separate from the speech model and are downloaded the first time they are
/// needed, into the same place as the Parakeet models.
@Observable
final class SpeakerDiarizationService: SpeakerTurnProviding {
    static let shared = SpeakerDiarizationService()

    /// The models are downloaded and loaded.
    private(set) var isReady = false
    /// 0…1 while the models are being downloaded or compiled, nil otherwise.
    private(set) var downloadProgress: Double?

    private var models: OfflineDiarizerModels?
    /// The load in flight, so a second caller waits for it instead of starting another.
    private var loadTask: Task<OfflineDiarizerModels, Error>?
    /// One pass at a time, and no sweep of the temporary directory while one runs.
    private let passes = InferenceGate()

    private init() {}

    /// Downloads (once) and loads the diarizer's models.
    func prepare() async throws {
        _ = try await loadedModels()
    }

    func turns(for url: URL, speakerCount: Int?) async throws -> [SpeakerTurn] {
        let models = try await loadedModels()
        var config = OfflineDiarizerConfig.default
        if let speakerCount {
            config = config.withSpeakers(exactly: speakerCount)
        }
        let segments = try await Self.runPass(on: passes, sweep: { await Self.sweepLeftoverAudio() }) {
            // The diarizer is heavy; keep it off the main actor.
            let work = Task.detached(priority: .userInitiated) {
                let manager = OfflineDiarizerManager(config: config)
                manager.initialize(models: models)
                return try await manager.process(url).segments.map {
                    (speaker: $0.speakerId, start: $0.startTimeSeconds, end: $0.endTimeSeconds)
                }
            }
            return try await withTaskCancellationHandler {
                try await work.value
            } onCancel: {
                work.cancel()
            }
        }
        return Self.turns(fromSegments: segments)
    }

    /// Deletes the temporary audio copies that passes cut short by a quit or a crash left
    /// behind. Waits for a pass in flight, whose copy is still in use.
    func cleanUpLeftoverAudio() async {
        _ = try? await Self.runPass(on: passes, sweep: {}) { await Self.sweepLeftoverAudio() }
    }

    /// Runs `pass` once the passes asked for before it have ended, as the diarizer cannot be
    /// stopped and two passes would share its models. `sweep` runs before the pass and again
    /// if it throws. A caller cancelled while it waits throws `CancellationError` and runs
    /// nothing.
    static func runPass<T>(
        on gate: InferenceGate, sweep: () async -> Void, _ pass: () async throws -> T
    ) async throws -> T {
        try await gate.run {
            await sweep()
            do {
                return try await pass()
            } catch {
                await sweep()
                throw error
            }
        }
    }

    /// The diarizer reads the file through a raw copy of its audio in the temporary directory
    /// and deletes the copy only when it returns. Called only while no pass runs.
    @concurrent
    private static func sweepLeftoverAudio() async {
        removeLeftoverAudio()
    }

    /// Deletes the files named `fluidaudio-streaming-*.raw` in `directory`, and nothing else.
    nonisolated static func removeLeftoverAudio(in directory: URL = FileManager.default.temporaryDirectory) {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name.hasPrefix("fluidaudio-streaming-") && name.hasSuffix(".raw") {
            let url = directory.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                continue
            }
            try? fileManager.removeItem(at: url)
        }
    }

    /// The diarizer's segments as turns, in time order, without empty ones.
    nonisolated static func turns(fromSegments segments: [(speaker: String, start: Float, end: Float)]) -> [SpeakerTurn] {
        segments
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
            .map { SpeakerTurn(speaker: $0.speaker, start: Double($0.start), end: Double($0.end)) }
    }

    private func loadedModels() async throws -> OfflineDiarizerModels {
        if let models { return models }
        if let loadTask { return try await loadTask.value }

        downloadProgress = 0
        // Downloading and compiling the models is slow; keep it off the main actor.
        let task = Task.detached(priority: .userInitiated) {
            try await OfflineDiarizerModels.load { progress in
                Task { @MainActor in
                    SpeakerDiarizationService.shared.reportProgress(progress.fractionCompleted)
                }
            }
        }
        loadTask = task
        defer {
            loadTask = nil
            downloadProgress = nil
        }
        let loaded = try await task.value
        models = loaded
        isReady = true
        return loaded
    }

    /// Ignores progress that arrives after the load has ended.
    private func reportProgress(_ fraction: Double) {
        guard loadTask != nil else { return }
        downloadProgress = fraction
    }
}
