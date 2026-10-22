import Foundation

public extension Localizable {

    /// The localized name for a certain locale.
    ///
    /// - Parameters:
    ///   - locale: The locale to use, by default `.current`.
    func localizedName(
        in locale: Locale = .current
    ) -> String {
        localizedName(in: locale, bundle: .keyboardCore)
    }
}

public extension Localizable {
    
    /// The localized text for a certain key, locale.
    ///
    /// - Parameters:
    ///   - key:
    ///   - locale: The locale to use, by default `.current`.
    static func localizedText(
        for key: String,
        in locale: Locale = .current
    ) -> String {
        localizedText(for: key, in: locale, bundle: .keyboardCore)
    }
    
    /// The localized text for a certain key, locale.
    ///
    /// - Parameters:
    ///   - key:
    ///   - locale: The locale to use, by default `.current`.
    func localizedText(
        for key: String,
        in locale: Locale = .current
    ) -> String {
        Self.localizedText(for: key, in: locale)
    }
}
