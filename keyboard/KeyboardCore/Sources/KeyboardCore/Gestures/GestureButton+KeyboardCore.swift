import SwiftUI

public extension View {
    
    /// Customize the keyboard button gesture configuration.
    func keyboardButtonGestureConfiguration(
        _ config: GestureButtonConfiguration
    ) -> some View {
        self.gestureButtonConfiguration(config)
    }
}
