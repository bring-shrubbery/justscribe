import CoreGraphics

public extension KeyboardActionHandler where Self == KeyboardPreviews.ActionHandler {

    static var preview: KeyboardActionHandler {
        KeyboardPreviews.ActionHandler()
    }
}

public extension KeyboardPreviews {

    class ActionHandler: KeyboardActionHandler {

        public init() {}
    }
}

public extension KeyboardPreviews.ActionHandler {

    func canHandle(_ gesture: Keyboard.Gesture, on action: KeyboardAction) -> Bool { false }
    func handle(_ action: KeyboardAction) {}
    func handle(_ suggestion: Autocomplete.Suggestion) {}
    func handle(_ gesture: Keyboard.Gesture, on action: KeyboardAction) {}
    func handleDrag(on action: KeyboardAction, from startLocation: CGPoint, to currentLocation: CGPoint) {}
    func triggerFeedback(for gesture: Keyboard.Gesture, on action: KeyboardAction) {}
    func triggerAudioFeedback(_ feedback: Feedback.Audio) {}
    func triggerHapticFeedback(_ feedback: Feedback.Haptic) {}
}
