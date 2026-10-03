//
//  JSONFile.swift
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

import Foundation

/// One JSON document in the container: atomic writes, ISO 8601 dates, and a damaged file set
/// aside as `<name>.broken` rather than overwritten.
nonisolated enum JSONFile {
    enum ReadResult<T> { case missing, loaded(T), damaged }

    static func read<T: Decodable>(_ type: T.Type, from url: URL) -> ReadResult<T> {
        guard let data = try? Data(contentsOf: url) else { return .missing }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let value = try? decoder.decode(T.self, from: data) { return .loaded(value) }
        return .damaged
    }

    /// Moves a damaged file out of the way; a previous `.broken` is replaced.
    static func setAside(_ url: URL) {
        let broken = url.appendingPathExtension("broken")
        try? FileManager.default.removeItem(at: broken)
        try? FileManager.default.moveItem(at: url, to: broken)
    }

    @discardableResult
    static func write<T: Encodable>(_ value: T, to url: URL) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(value).write(to: url, options: .atomic)
            return true
        } catch {
            print("JSONFile: \(url.lastPathComponent) not saved: \(error)")
            return false
        }
    }

    /// `Application Support/<bundle id>/<name>` inside the container.
    static func containerURL(_ name: String) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "com.quassum.justscribe"
        return support.appendingPathComponent(bundleID).appendingPathComponent(name)
    }
}
