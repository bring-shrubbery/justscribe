import SwiftUI

public extension Emoji {
    
    struct KeyboardWrapper: View {
        
        init(
            actionHandler: KeyboardActionHandler,
            keyboardContext: KeyboardContext,
            calloutContext: CalloutContext?,
            styleService: KeyboardStyleService
        ) {}

        public var body: some View {
            EmptyView()
        }
        
        static var isEmptyPlaceholder: Bool { true }
    }
}
