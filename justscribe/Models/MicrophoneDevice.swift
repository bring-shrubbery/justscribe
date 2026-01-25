//
//  MicrophoneDevice.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import Foundation
import AVFoundation

struct MicrophoneDevice: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var name: String
    var isAvailable: Bool
    var priority: Int

    init(id: String, name: String, isAvailable: Bool = true, priority: Int = 0) {
        self.id = id
        self.name = name
        self.isAvailable = isAvailable
        self.priority = priority
    }

    #if os(macOS)
    init(from device: AVCaptureDevice, priority: Int = 0) {
        self.id = device.uniqueID
        self.name = device.localizedName
        self.isAvailable = true
        self.priority = priority
    }
    #endif
}
