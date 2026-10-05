//
//  MicrophoneDeviceTests.swift
//  justscribeTests
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

import Testing
@testable import justscribe

struct MicrophoneDeviceTests {
    private let builtIn = MicrophoneDevice(id: "built-in", name: "MacBook Pro Microphone")
    private let airPods = MicrophoneDevice(id: "airpods", name: "AirPods Pro", isBluetooth: true)
    private let usb = MicrophoneDevice(id: "usb", name: "USB Microphone")

    @Test func aHeadsetThatConnectsIsNotChosenOverTheBuiltInMicrophone() {
        // The headset comes first, as macOS lists the new default input first.
        let chosen = MicrophoneDevice.preferred(in: [airPods, builtIn], priority: [], banned: [])
        #expect(chosen == builtIn)
    }

    @Test func theUsersOrderWinsEvenForAHeadset() {
        let chosen = MicrophoneDevice.preferred(in: [builtIn, airPods], priority: ["airpods", "built-in"], banned: [])
        #expect(chosen == airPods)
    }

    @Test func aHeadsetIsUsedWhenItIsTheOnlyMicrophone() {
        #expect(MicrophoneDevice.preferred(in: [airPods], priority: [], banned: []) == airPods)
    }

    @Test func bannedAndUnavailableMicrophonesAreSkipped() {
        var unplugged = usb
        unplugged.isAvailable = false
        let chosen = MicrophoneDevice.preferred(
            in: [unplugged, builtIn, airPods], priority: ["usb", "built-in"], banned: ["built-in"])
        #expect(chosen == airPods)
        #expect(MicrophoneDevice.preferred(in: [builtIn], priority: [], banned: ["built-in"]) == nil)
    }

    @Test func aPriorityEntryThatIsGoneFallsThroughToTheRest() {
        let chosen = MicrophoneDevice.preferred(in: [airPods, usb], priority: ["built-in"], banned: [])
        #expect(chosen == usb)
    }

    @Test func bluetoothTransportCodesAreRecognised() {
        #expect(MicrophoneDevice.isBluetoothTransport(0x626C_7565))  // 'blue'
        #expect(MicrophoneDevice.isBluetoothTransport(0x626C_6561))  // 'blea'
        #expect(!MicrophoneDevice.isBluetoothTransport(0x626C_746E)) // 'bltn', built-in
        #expect(!MicrophoneDevice.isBluetoothTransport(0x7573_6220)) // 'usb '
    }
}
