import Foundation
import SwiftUI

extension Bundle {
    
    /// The main library bundle (for EmojiKit).
    static var library: Bundle { .keyboardCore }
}

public extension Bundle {

    /// The KeyboardCore bundle.
    static var keyboardCore: Bundle { .module }
}
