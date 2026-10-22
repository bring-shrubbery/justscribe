import Foundation

public extension KeyboardAction {
    
    /// The input callout text to present for the action.
    var inputCalloutText: String? {
        switch self {
        case .character(let char): char
        case .emoji(let emoji): emoji.char
        default: nil
        }
    }
}
