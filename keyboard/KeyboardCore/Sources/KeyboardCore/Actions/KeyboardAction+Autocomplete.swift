import Foundation

public extension KeyboardAction {

    /// Whether the action should apply autocorrect suggestions.
    var shouldApplyAutocorrectSuggestion: Bool {
        switch self {
        case .character(let char): char.isAutocorrectTrigger
        case .primary(let type): type.isSystemAction
        case .space: true
        default: false
        }
    }
    
    /// Whether the action should re-insert autocomplete inserted spaces.
    var shouldReinsertAutocompleteInsertedSpace: Bool {
        shouldRemoveAutocompleteInsertedSpace
    }
    
    /// Whether the action should remove autocomplete inserted spaces.
    var shouldRemoveAutocompleteInsertedSpace: Bool {
        switch self {
        case .character(let char): char.isWordDelimiter && self != .space
        default: false
        }
    }
}
