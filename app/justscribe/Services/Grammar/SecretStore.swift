//
//  SecretStore.swift
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
import Security

/// Where API keys live. The app keeps them in the keychain; tests keep them in memory.
protocol SecretStore: AnyObject {
    func secret(for account: String) -> String?
    /// Stores `secret`, or removes the entry when it is nil.
    func set(_ secret: String?, for account: String) throws
}

nonisolated struct KeychainError: LocalizedError, Equatable {
    let status: OSStatus
    var errorDescription: String? {
        "Couldn't save to the keychain (\(SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"))."
    }
}

/// Generic-password items in the app's keychain, one per account. The sandbox limits them to
/// this app; nothing is written anywhere else, and the key never appears in logs or defaults.
final class KeychainSecretStore: SecretStore {
    static let shared = KeychainSecretStore(service: (Bundle.main.bundleIdentifier ?? "com.quassum.justscribe") + ".grammar")

    private let service: String

    init(service: String) {
        self.service = service
    }

    private func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func secret(for account: String) -> String? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func set(_ secret: String?, for account: String) throws {
        guard let secret, !secret.isEmpty else {
            let status = SecItemDelete(query(account) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
            return
        }
        let data = Data(secret.utf8)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query(account) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(account)
            add[kSecValueData as String] = data
            let added = SecItemAdd(add as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }
}
