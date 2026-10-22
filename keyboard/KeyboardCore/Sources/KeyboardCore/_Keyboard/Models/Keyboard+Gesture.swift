import Foundation

public extension Keyboard {

    /// This enum defines various keyboard gestures that can
    /// be used to interact with a keyboard.
    enum Gesture: String, CaseIterable, KeyboardModel {

        /// Triggers when a button is double tapped.
        case doubleTap
        
        /// Triggers when a button is pressed down.
        case press

        /// Triggers when a button is released.
        case release
        
        /// Triggers when a button is long pressed.
        case longPress
        
        /// Triggers repeatedly while a button is pressed.
        case repeatPress
        
        /// Triggers when a button gesture ends.
        case end
    }
}

public extension Keyboard.Gesture {

    /// A ``Keyboard/Gesture/repeatPress`` shorthand.
    static let `repeat` = repeatPress
}

public extension Keyboard.Gesture {

    /// The gesture's unique identifier.
    var id: String { rawValue }
}
