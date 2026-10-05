//
//  MicrophoneDevice.swift
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
import AVFoundation

struct MicrophoneDevice: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var name: String
    var isAvailable: Bool
    var priority: Int
    /// A Bluetooth headset's microphone. Using it switches the headset to its hands-free
    /// profile, so everything it plays drops to call quality until the recording ends.
    var isBluetooth: Bool

    init(id: String, name: String, isAvailable: Bool = true, priority: Int = 0, isBluetooth: Bool = false) {
        self.id = id
        self.name = name
        self.isAvailable = isAvailable
        self.priority = priority
        self.isBluetooth = isBluetooth
    }

    #if os(macOS)
    init(from device: AVCaptureDevice, priority: Int = 0) {
        self.id = device.uniqueID
        self.name = device.localizedName
        self.isAvailable = true
        self.priority = priority
        self.isBluetooth = Self.isBluetoothTransport(device.transportType)
    }

    /// Core Audio's transport types are four-character codes: 'blue' for Bluetooth and
    /// 'blea' for Bluetooth Low Energy.
    nonisolated static func isBluetoothTransport(_ transportType: Int32) -> Bool {
        transportType == 0x626C_7565 || transportType == 0x626C_6561
    }
    #endif

    /// The microphone to record with. The first one in `priority` that is available and not
    /// banned wins: that order is the user's. With no such microphone, the first available
    /// one that is not a Bluetooth headset, so connecting headphones does not silently move
    /// recording to them and put them into call quality; a Bluetooth microphone is chosen
    /// without being asked for only when nothing else is there.
    nonisolated static func preferred(
        in devices: [MicrophoneDevice], priority: [String], banned: [String]
    ) -> MicrophoneDevice? {
        let banned = Set(banned)
        let usable = devices.filter { $0.isAvailable && !banned.contains($0.id) }
        for id in priority {
            if let device = usable.first(where: { $0.id == id }) { return device }
        }
        return usable.first { !$0.isBluetooth } ?? usable.first
    }
}
