import Foundation

public extension KeyboardLayout {

    static var preview: KeyboardLayout {
        KeyboardPreviews.LayoutService()
            .keyboardLayout(for: .preview)
    }
}

public extension KeyboardLayoutService where Self == KeyboardPreviews.LayoutService {

    static var preview: KeyboardLayoutService {
        KeyboardPreviews.LayoutService()
    }
}

public extension KeyboardPreviews {
 
    class LayoutService: KeyboardLayoutService {

        public init(keyboardContext: KeyboardContext = .preview) {
            service = KeyboardLayout.StandardLayoutService()
        }

        private let service: KeyboardLayoutService

        public func keyboardLayout(for context: KeyboardContext) -> KeyboardLayout {
            service.keyboardLayout(for: context)
        }
    }
}
