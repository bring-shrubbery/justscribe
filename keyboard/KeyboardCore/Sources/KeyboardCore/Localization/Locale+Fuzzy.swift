import Foundation
import SwiftUI

public extension Locale {
    
    /// Try to create a locale from a fuzzy name.
    init?(fuzzyName: String) {
        let all = Self.keyboardSupported
        let match = all.first { fuzzyName.matches($0) }
        guard let match = match else { return nil }
        self = match
    }
}

private extension String {

    func formattedForLocaleMatch() -> String {
        self.replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }

    func matches(_ locale: Locale) -> Bool {
        let value = self.formattedForLocaleMatch()
        let rawName = locale.keyboardName.formattedForLocaleMatch()
        let id = locale.identifier.formattedForLocaleMatch()
        return value.matches(rawName) || value.matches(id)
    }

    func matches(_ string: String) -> Bool {
        caseInsensitiveCompare(string) == .orderedSame
    }
}
