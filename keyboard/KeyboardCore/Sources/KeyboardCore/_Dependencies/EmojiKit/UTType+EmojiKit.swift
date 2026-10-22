import UniformTypeIdentifiers

public extension UTType {
    
    /// A custom uniform type for an ``Emoji``.
    ///
    /// The explicit type ID is `com.emojikit.emoji`.
    static var emoji: UTType {
        .init(
            exportedAs: "com.emojikit.emoji",
            conformingTo: .data
        )
    }
    
    /// A custom uniform type for an ``EmojiCategory``.
    ///
    /// The explicit type ID is `com.emojikit.emojicategory`.
    static var emojiCategory: UTType {
        .init(
            exportedAs: "com.emojikit.emojicategory",
            conformingTo: .data
        )
    }
}
