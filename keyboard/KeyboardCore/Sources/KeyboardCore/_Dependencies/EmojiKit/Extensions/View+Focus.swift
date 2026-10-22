import SwiftUI

extension View {
    
    @ViewBuilder
    func prefersFocusable(_ bool: Bool) -> some View {
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *) {
            self.focusable(bool)
        } else {
            self
        }
    }
    
    @ViewBuilder
    func prefersFocusEffectDisabled(_ bool: Bool) -> some View {
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *) {
            self.focusEffectDisabled(bool)
        } else {
            self
        }
    }
}
