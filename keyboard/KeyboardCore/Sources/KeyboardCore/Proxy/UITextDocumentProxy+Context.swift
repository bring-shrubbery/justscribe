#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit

public extension UITextDocumentProxy {

    /// Get the document context (the text) before and after
    /// the input cursor.
    ///
    /// This property does not return the full document text.
    /// A keyboard extension has limited document access and
    /// can stop looking for more text at any time.
    var documentContext: String? {
        let before = documentContextBeforeInput ?? ""
        let after = documentContextAfterInput ?? ""
        return before + after
    }
    
    /// Whether the proxy is currently reading the full text
    /// from the current document.
    var isReadingFullDocumentContext: Bool {
        get { FullDocumentContextReaderState.isReadingFullDocumentContext }
        set { FullDocumentContextReaderState.isReadingFullDocumentContext = newValue }
    }
}
#endif
