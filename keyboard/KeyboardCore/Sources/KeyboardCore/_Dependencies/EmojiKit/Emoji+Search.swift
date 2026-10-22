import Foundation

public extension Emoji {

    /// Whether the emoji matches a certain query.
    func matches(
        _ query: String,
        in locale: Locale = .current
    ) -> Bool {
        guard query.hasContent else { return true }
        if self.char == query { return true }
        if unicodeName.matches(query) { return true }
        return localizedName(in: locale).matches(query)
    }
}

public extension Collection where Element == Emoji {

    // Find all emojis that match a certain search query.
    func matching(
        _ query: String,
        in locale: Locale = .current
    ) -> [Emoji] {
        guard query.hasContent else { return Array(self) }
        return filter { $0.matches(query, in: locale) }
    }
}

private extension String {

    var hasContent: Bool {
        !trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func matches(_ query: String) -> Bool {
        localizedCaseInsensitiveContains(query)
    }
}
