import Foundation

public extension Locale {

    /// Get the character direction for the locale.
    var characterDirection: Locale.LanguageDirection {
        Locale.characterDirection(forLanguage: languageCode ?? "")
    }

    /// Whether the ``lineDirection`` is `.bottomToTop`.
    var isBottomToTop: Bool {
        lineDirection == .bottomToTop
    }

    /// Whether the ``lineDirection``  is `.topToBottom`.
    var isTopToBottom: Bool {
        lineDirection == .topToBottom
    }

    /// Whether the ``characterDirection``  is `.leftToRight`.
    var isLeftToRight: Bool {
        characterDirection == .leftToRight
    }

    /// Whether the ``characterDirection``  is `.rightToLeft`.
    var isRightToLeft: Bool {
        characterDirection == .rightToLeft
    }

    /// Get the line direction for the locale.
    var lineDirection: Locale.LanguageDirection {
        Locale.lineDirection(forLanguage: languageCode ?? "")
    }
}
