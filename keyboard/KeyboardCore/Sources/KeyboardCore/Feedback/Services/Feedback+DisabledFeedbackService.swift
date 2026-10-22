import Foundation

public extension FeedbackService where Self == Feedback.DisabledFeedbackService {

    /// Create a disabled feedback service instance.
    static var disabled: Self {
        Feedback.DisabledFeedbackService()
    }
}

extension Feedback {

    /// This service can be used to disable all feedback.
    ///
    /// This service can also be resolved with the shorthand
    /// ``FeedbackService/disabled``.
    open class DisabledFeedbackService: FeedbackService {

        /// Create a disabled feedback service.
        public init() {}

        open func triggerAudioFeedback(_ audio: Feedback.Audio) {}

        open func triggerHapticFeedback(_ feedback: Feedback.Haptic) {}
    }
}
