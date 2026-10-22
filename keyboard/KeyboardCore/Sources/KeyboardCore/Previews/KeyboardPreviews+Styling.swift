import SwiftUI

public extension KeyboardStyleService where Self == KeyboardPreviews.StyleService {

    static var preview: KeyboardStyleService {
        KeyboardPreviews.StyleService()
    }
}

public extension KeyboardPreviews {
    
    class StyleService: KeyboardStyle.StandardStyleService {

        init() {
            super.init(keyboardContext: .preview)
        }
    }
}
