//
//  SpeechRecognition.swift
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
import Speech

/// On-device speech recognition through Apple's `SpeechAnalyzer`, which needs
/// no model in the app: iOS downloads and shares the language's assets.
///
/// This is the first engine to prove the keyboard flow; Parakeet through
/// FluidAudio, as on the Mac, can sit behind the same `start` / `finish` shape.
nonisolated enum SpeechRecognition {

    enum Failure: LocalizedError {
        case unsupportedLocale
        case noAudioFormat

        var errorDescription: String? {
            switch self {
            case .unsupportedLocale: "On-device speech recognition does not support this language."
            case .noAudioFormat: "On-device speech recognition has no audio format for this language."
            }
        }
    }

    /// What one recording needs, resolved once per session.
    struct Configuration: Sendable {
        let locale: Locale
        let format: AVAudioFormat
        let usesSpeechTranscriber: Bool
    }

    /// Resolves the language, downloads its assets when missing and finds the
    /// audio format the analyzer wants. Slow the first time only.
    static func prepare(for requested: Locale = .current) async throws -> Configuration {
        let usesSpeechTranscriber = SpeechTranscriber.isAvailable
        let locale: Locale? = if usesSpeechTranscriber {
            await SpeechTranscriber.supportedLocale(equivalentTo: requested)
        } else {
            await DictationTranscriber.supportedLocale(equivalentTo: requested)
        }
        guard let locale else { throw Failure.unsupportedLocale }

        let module = makeModule(locale: locale, usesSpeechTranscriber: usesSpeechTranscriber)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw Failure.noAudioFormat
        }
        return Configuration(locale: locale, format: format, usesSpeechTranscriber: usesSpeechTranscriber)
    }

    static func makeModule(locale: Locale, usesSpeechTranscriber: Bool) -> any SpeechModule {
        if usesSpeechTranscriber {
            SpeechTranscriber(locale: locale, preset: .transcription)
        } else {
            DictationTranscriber(locale: locale, preset: .longDictation)
        }
    }
}

/// One recording's transcription: audio goes in while the user speaks, so the
/// text is nearly ready when they stop.
///
/// `append` is called on the audio thread, everything else on the main actor.
nonisolated final class TranscriptionRun: @unchecked Sendable {

    private let analyzer: SpeechAnalyzer
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private let converter: PCMConverter
    private let text: Task<String, Error>

    init(configuration: SpeechRecognition.Configuration, inputFormat: AVAudioFormat) throws {
        let module = SpeechRecognition.makeModule(
            locale: configuration.locale,
            usesSpeechTranscriber: configuration.usesSpeechTranscriber
        )
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        analyzer = SpeechAnalyzer(modules: [module])
        input = continuation
        converter = try PCMConverter(from: inputFormat, to: configuration.format)

        let analyzer = analyzer
        text = Task {
            try await analyzer.start(inputSequence: stream)
            return try await Self.collectText(from: module)
        }
    }

    /// Feeds one microphone buffer. Audio thread only.
    func append(_ buffer: AVAudioPCMBuffer) {
        guard let converted = converter.convert(buffer) else { return }
        input.yield(AnalyzerInput(buffer: converted))
    }

    /// Ends the audio and returns the whole transcript.
    func finish() async throws -> String {
        input.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await text.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() async {
        input.finish()
        await analyzer.cancelAndFinishNow()
        text.cancel()
    }

    private static func collectText(from module: any SpeechModule) async throws -> String {
        var transcript = ""
        if let module = module as? SpeechTranscriber {
            for try await result in module.results where result.isFinal {
                transcript += String(result.text.characters)
            }
        } else if let module = module as? DictationTranscriber {
            for try await result in module.results where result.isFinal {
                transcript += String(result.text.characters)
            }
        }
        return transcript
    }
}

/// Converts microphone buffers to the analyzer's format. Audio thread only.
nonisolated final class PCMConverter {

    private let converter: AVAudioConverter
    private let output: AVAudioFormat

    init(from input: AVAudioFormat, to output: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: input, to: output) else {
            throw SpeechRecognition.Failure.noAudioFormat
        }
        self.converter = converter
        self.output = output
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let ratio = output.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let converted = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return nil }
        nonisolated(unsafe) var supplied = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && converted.frameLength > 0 ? converted : nil
    }
}
