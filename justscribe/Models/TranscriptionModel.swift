//
//  TranscriptionModel.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import Foundation
import SwiftData

enum ModelAccuracy: String, Codable {
    case low
    case medium
    case high
    case veryHigh

    var displayName: String {
        switch self {
        case .low: return "Lower"
        case .medium: return "Medium"
        case .high: return "High"
        case .veryHigh: return "Highest"
        }
    }
}

enum ModelSpeed: String, Codable {
    case fast
    case medium
    case slow
    case verySlow

    var displayName: String {
        switch self {
        case .fast: return "Fast"
        case .medium: return "Medium"
        case .slow: return "Slow"
        case .verySlow: return "Very Slow"
        }
    }
}

@Model
final class TranscriptionModel {
    @Attribute(.unique) var id: String
    var name: String
    var modelDescription: String
    var size: Int64
    var downloadURLString: String
    var localPathString: String?
    var isDownloaded: Bool = false
    var downloadProgress: Double = 0.0
    var isRecommended: Bool = false

    @Attribute var accuracyRaw: String = ModelAccuracy.medium.rawValue
    var accuracy: ModelAccuracy {
        get { ModelAccuracy(rawValue: accuracyRaw) ?? .medium }
        set { accuracyRaw = newValue.rawValue }
    }

    @Attribute var speedRaw: String = ModelSpeed.medium.rawValue
    var speed: ModelSpeed {
        get { ModelSpeed(rawValue: speedRaw) ?? .medium }
        set { speedRaw = newValue.rawValue }
    }

    var downloadURL: URL? {
        URL(string: downloadURLString)
    }

    var localPath: URL? {
        get { localPathString.flatMap { URL(string: $0) } }
        set { localPathString = newValue?.absoluteString }
    }

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    init(
        id: String,
        name: String,
        description: String,
        size: Int64,
        downloadURL: URL,
        accuracy: ModelAccuracy = .medium,
        speed: ModelSpeed = .medium,
        isRecommended: Bool = false
    ) {
        self.id = id
        self.name = name
        self.modelDescription = description
        self.size = size
        self.downloadURLString = downloadURL.absoluteString
        self.accuracy = accuracy
        self.speed = speed
        self.isRecommended = isRecommended
    }
}

// MARK: - Default Models

extension TranscriptionModel {
    static let availableModels: [(id: String, name: String, description: String, size: Int64, accuracy: ModelAccuracy, speed: ModelSpeed, recommended: Bool)] = [
        (
            id: "whisper-tiny",
            name: "Whisper Tiny",
            description: "Fastest model with lower accuracy. Good for quick notes.",
            size: 75_000_000,
            accuracy: .low,
            speed: .fast,
            recommended: false
        ),
        (
            id: "whisper-base",
            name: "Whisper Base",
            description: "Good balance of speed and accuracy. Recommended for most users.",
            size: 142_000_000,
            accuracy: .medium,
            speed: .fast,
            recommended: true
        ),
        (
            id: "whisper-small",
            name: "Whisper Small",
            description: "Better accuracy with moderate speed.",
            size: 466_000_000,
            accuracy: .high,
            speed: .medium,
            recommended: false
        ),
        (
            id: "whisper-medium",
            name: "Whisper Medium",
            description: "High accuracy for professional use.",
            size: 1_500_000_000,
            accuracy: .high,
            speed: .slow,
            recommended: false
        ),
        (
            id: "whisper-large-v3",
            name: "Whisper Large v3",
            description: "Maximum accuracy. Best for critical transcriptions.",
            size: 3_000_000_000,
            accuracy: .veryHigh,
            speed: .verySlow,
            recommended: false
        )
    ]
}
