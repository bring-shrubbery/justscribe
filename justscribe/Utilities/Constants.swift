//
//  Constants.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import Foundation

enum Constants {
    static let appName = "JustScribe"
    static let bundleIdentifier = "com.quassum.justscribe"

    enum URLs {
        static let website = URL(string: "https://justscribe.app")!
        static let privacyPolicy = URL(string: "https://justscribe.app/privacy")!
        static let termsOfService = URL(string: "https://justscribe.app/terms")!
        static let credits = URL(string: "https://justscribe.app/credits")!
        static let support = URL(string: "https://justscribe.app/support")!
    }

    enum Storage {
        static var modelsDirectory: URL {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let modelsDir = appSupport.appendingPathComponent(bundleIdentifier).appendingPathComponent("Models")

            if !FileManager.default.fileExists(atPath: modelsDir.path) {
                try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
            }

            return modelsDir
        }
    }

    enum SupportedLanguages {
        static let all: [(code: String, name: String)] = [
            ("en", "English"),
            ("es", "Spanish"),
            ("fr", "French"),
            ("de", "German"),
            ("it", "Italian"),
            ("pt", "Portuguese"),
            ("nl", "Dutch"),
            ("pl", "Polish"),
            ("ru", "Russian"),
            ("zh", "Chinese"),
            ("ja", "Japanese"),
            ("ko", "Korean"),
        ]
    }
}
