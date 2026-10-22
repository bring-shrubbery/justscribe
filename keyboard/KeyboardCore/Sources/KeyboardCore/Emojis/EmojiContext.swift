import SwiftUI

/// This class has observable states and persistent settings
/// for emoji-related functionality.
///
/// This class also has observable auto-persisted ``settings``
/// that can be used to configure emojis.
///
/// KeyboardCore will create an instance of this context, and
/// inject into the environment, when you set up KeyboardCore
/// as shown in <doc:Getting-Started-Article>.
public class EmojiContext: ObservableObject {

    /// Create an autocomplete context instance.
    public init() {
        settings = .init()
    }

    // MARK: - Settings

    /// Auto-persisted emoji settings.
    @Published public var settings: EmojiSettings
}
