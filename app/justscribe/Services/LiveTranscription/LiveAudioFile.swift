//
//  LiveAudioFile.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 05/10/2026.
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
import Foundation

/// Writes a live transcription's 16 kHz mono audio to a small AAC file as it arrives, so the
/// speaker pass at the end can read it back without the whole recording ever being in memory.
/// An actor: encoding stays off the main actor, and appends keep their order.
actor LiveAudioFile {
    let url: URL
    private var file: AVAudioFile?
    /// Set by `discard()`: audio still on its way is dropped instead of recreating the file.
    private var isDiscarded = false
    private let format = AVAudioFormat(standardFormatWithSampleRate: HistoryAudioWriter.sampleRate, channels: 1)!

    /// A new file in `directory`, named so a sweep can tell it apart.
    init(directory: URL = FileManager.default.temporaryDirectory) {
        url = directory.appendingPathComponent("justscribe-live-\(UUID().uuidString).m4a")
    }

    func append(_ samples: [Float]) {
        guard !samples.isEmpty, !isDiscarded else { return }
        do {
            if file == nil {
                file = try AVAudioFile(forWriting: url, settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: HistoryAudioWriter.sampleRate,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderBitRateKey: HistoryAudioWriter.bitRate,
                ], commonFormat: .pcmFormatFloat32, interleaved: false)
            }
            guard let file,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = buffer.floatChannelData?[0] else { return }
            samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            try file.write(from: buffer)
        } catch {
            print("Live audio file: \(error)")
        }
    }

    /// Closes the file; nil when nothing was written. The caller deletes it when done.
    func finish() -> URL? {
        guard let file else { return nil }
        file.close()
        self.file = nil
        return url
    }

    /// Deletes the file, written or not.
    func discard() {
        isDiscarded = true
        file?.close()
        file = nil
        try? FileManager.default.removeItem(at: url)
    }
}
