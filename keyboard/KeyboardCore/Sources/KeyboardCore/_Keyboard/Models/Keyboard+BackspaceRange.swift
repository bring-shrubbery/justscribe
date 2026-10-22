import Foundation

public extension Keyboard {
    
    /// This enum defines how much the backspace key deletes.
    enum BackspaceRange: String, CaseIterable, Identifiable, KeyboardModel {
        
        /// Delete a single char at a time.
        case character
        
        /// Delete an entire word at a time.
        case word
        
        /// Delete an entire sentence at a time.
        case sentence
    }
}

public extension Keyboard.BackspaceRange {
    
    var id: String { rawValue }
}
