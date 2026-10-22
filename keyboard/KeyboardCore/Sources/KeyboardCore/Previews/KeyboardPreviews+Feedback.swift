import CoreGraphics

public extension FeedbackService where Self == Feedback.DisabledFeedbackService {

    static var preview: Self {
        Feedback.DisabledFeedbackService()
    }
}
