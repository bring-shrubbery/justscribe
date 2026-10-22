import Foundation

public extension Emoji {
    
    /// Register a user selection for the emoji.
    ///
    /// This will insert the selected emoji first within the
    /// ``EmojiCategory/Persisted/recent`` category.
    func registerUserSelection() {
        EmojiCategory.Persisted.recent.addEmoji(self)
    }
}
