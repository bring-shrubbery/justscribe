import Foundation

public extension Emoji.KeyboardStyle {

    /// The standard emoji keyboard style for a context.
    static func standard(for context: KeyboardContext) -> Self {
        .init()
    }

    /// The emoji keyboard style for a phone.
    static func optimized(for context: KeyboardContext) -> Self {
        .init()
    }
}
