import CoreGraphics

/// This protocol can be implemented by any type that can be
/// used to handle drag gestures.
public protocol DragGestureHandler {
    
    /// Handle a drag gesture from start to current location.
    func handleDragGesture(
        from startLocation: CGPoint,
        to currentLocation: CGPoint
    )
}
