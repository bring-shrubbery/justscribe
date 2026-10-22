import Foundation
import SwiftUI

#if os(iOS) || os(tvOS) || os(visionOS)
public extension KeyboardInputViewController {

    static var preview: KeyboardInputViewController {
        KeyboardPreviews.InputViewController()
    }
}

public extension KeyboardPreviews {
    
    class InputViewController: KeyboardInputViewController {}
}
#endif

public extension Keyboard.Services {
    
    static var preview: Keyboard.Services {
        Keyboard.Services(state: .preview)
    }
}

public extension Keyboard.State {
    
    static var preview: Keyboard.State {
        Keyboard.State()
    }
}

public extension KeyboardContext {
    
    static var preview: KeyboardContext {
        KeyboardContext()
    }
}

public extension View {

    /// Prepare the view with preview environments.
    func keyboardPreview(
        keyboardContext: KeyboardContext = .preview
    ) -> some View {
        self.environmentObject(keyboardContext)
            .environmentObject(CalloutContext.preview)
    }
}
