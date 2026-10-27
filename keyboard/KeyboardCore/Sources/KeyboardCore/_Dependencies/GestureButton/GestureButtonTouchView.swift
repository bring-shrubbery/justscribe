import SwiftUI
import UIKit

/// Where a touch on a gesture button is, relative to the button.
public struct GestureButtonDragValue: Equatable, Sendable {

    public init(location: CGPoint, startLocation: CGPoint) {
        self.location = location
        self.startLocation = startLocation
    }

    /// The current location of the touch.
    public var location: CGPoint

    /// Where the touch began.
    public var startLocation: CGPoint

    /// How far the touch has moved since it began.
    public var translation: CGSize {
        CGSize(width: location.x - startLocation.x, height: location.y - startLocation.y)
    }
}

/// Feeds a gesture button from UIKit touches instead of a SwiftUI `DragGesture`.
///
/// In iOS 27 a `DragGesture` on a keyboard key can deliver its first change late,
/// sometimes only when the finger lifts or a second later, which drops or delays
/// keystrokes. `touchesBegan` arrives as soon as the finger lands.
struct GestureButtonTouchView: UIViewRepresentable {

    var onChanged: (GestureButtonDragValue) -> Void
    var onEnded: (GestureButtonDragValue) -> Void

    func makeUIView(context: Context) -> TouchView {
        let view = TouchView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = false
        return view
    }

    func updateUIView(_ view: TouchView, context: Context) {
        view.onChanged = onChanged
        view.onEnded = onEnded
    }

    final class TouchView: UIView {

        var onChanged: ((GestureButtonDragValue) -> Void)?
        var onEnded: ((GestureButtonDragValue) -> Void)?

        private var touch: UITouch?
        private var startLocation = CGPoint.zero

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard touch == nil, let first = touches.first else { return }
            touch = first
            startLocation = first.location(in: self)
            onChanged?(.init(location: startLocation, startLocation: startLocation))
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch, touches.contains(touch) else { return }
            onChanged?(.init(location: touch.location(in: self), startLocation: startLocation))
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch, touches.contains(touch) else { return }
            self.touch = nil
            onEnded?(.init(location: touch.location(in: self), startLocation: startLocation))
        }

        /// A cancelled touch ends outside the button, so it releases without typing.
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch, touches.contains(touch) else { return }
            self.touch = nil
            onEnded?(.init(location: CGPoint(x: -1, y: -1), startLocation: startLocation))
        }
    }
}
