import Foundation

extension EmojiCategory: Localizable {
    
    /// The `Localizable.strings` key to use when localizing.
    public var localizationKey: String {
        "EmojiCategory.\(id)"
    }
}

extension EmojiCategory.Persisted: Localizable {
    
    /// The `Localizable.strings` key to use when localizing.
    public var localizationKey: String {
        "EmojiCategory.\(id)"
    }
}
