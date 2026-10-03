//
//  HistoryPlayback.swift
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

import AVFoundation
import Foundation
import Observation

/// Plays one kept recording at a time.
@Observable
final class HistoryPlayback: NSObject, AVAudioPlayerDelegate {
    private(set) var playingURL: URL?
    var isPlaying: Bool { playingURL != nil }
    private var player: AVAudioPlayer?

    func play(_ url: URL) {
        stop()
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.delegate = self
        self.player = player
        playingURL = url
        player.play()
    }

    func stop() {
        player?.stop()
        player = nil
        playingURL = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}
