import Foundation

/// This static class is used as `UITextDocumentProxy` state
/// when reading the full document context.
final class FullDocumentContextReaderState {

    private init() {}

    static var isReadingFullDocumentContext = false
}
