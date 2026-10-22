import Foundation

public extension Bundle {

    /// Get whether or not the bundle is an extension.
    var isExtension: Bool {
        bundlePath.hasSuffix(".appex")
    }
}
