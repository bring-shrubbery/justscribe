//
//  Constants.swift
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

enum Constants {
    static let appName = "JustScribe"
    static let bundleIdentifier = "com.quassum.justscribe"

    enum URLs {
        static let website = URL(string: "https://quassum.com/apps/justscribe")!
        static let privacyPolicy = URL(string: "https://quassum.com/apps/justscribe/privacy")!
        static let termsOfService = URL(string: "https://quassum.com/terms")!
        static let credits = URL(string: "https://quassum.com/apps/justscribe#credits")!
        static let support = URL(string: "https://quassum.com/apps/justscribe#support")!
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
