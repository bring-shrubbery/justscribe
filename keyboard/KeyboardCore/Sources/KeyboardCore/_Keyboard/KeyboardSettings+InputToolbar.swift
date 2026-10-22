import SwiftUI

public extension KeyboardSettings {
    
    /// This enum defines various input toolbar modes, which
    /// can be used to set how an input toolbar is displayed.
    ///
    /// The reason why this type is used in settings instead
    /// of ``Keyboard/InputToolbarDisplayMode`` is that this
    /// type can be persisted, while the display mode cannot.
    enum InputToolbarType: String, KeyboardModel {

        /// Display a toolbar based on the native behavior.
        case automatic

        /// Display a fixed set of characters from settings.
        case characters
        
        /// Display contextual numbers or symbols.
        case numbers
        
        /// Display the most recently used emojis.
        case recentEmojis

        /// Remove the input toolbar altogether.
        case none
    }
    
    /// The input toolbar display mode.
    ///
    /// This value is derived from ``inputToolbarType``, and
    /// uses ``inputToolbarCharacters`` for input characters.
    var inputToolbarDisplayMode: Keyboard.InputToolbarDisplayMode {
        switch inputToolbarType {
        case .automatic: .automatic
        case .characters: .characters(charactersString)
        case .numbers: .numbers
        case .recentEmojis: .characters(recentEmojisString)
        case .none: .none
        }
    }
}

private extension KeyboardSettings {
    
    var maxCount: Int {
        inputToolbarCharactersMaxCount
    }
    
    var charactersString: String {
        inputToolbarCharacters.inputToolbarCapped(maxCount)
    }

    var recentEmojisString: String {
        let recentString = EmojiCategory.persisted(.recent)
            .emojis
            .prefix(10)
            .map { $0.char }.joined()
        let placeholders = "😀🤩😍😂👍👎👋🙌🙏❤️"
        let joined = recentString + placeholders
        return joined.inputToolbarCapped(maxCount)
    }
}

private extension String {
    
    func inputToolbarCapped(_ count: Int) -> String {
        String(self.prefix(count))
    }
}
