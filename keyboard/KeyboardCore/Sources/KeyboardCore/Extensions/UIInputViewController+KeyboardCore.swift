#if os(iOS)
import Foundation
import UIKit

public extension UIInputViewController {

    /// Whether this controller is KeyboardCore enabled.
    var isKeyboardCoreEnabledController: Bool {
        self is KeyboardInputViewController
    }
}
#endif
