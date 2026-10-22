import CoreGraphics

extension CGSize {
    
    /// Limit a size to another size.
    func limited(to size: CGSize) -> CGSize {
        CGSize(
            width: min(width, size.width),
            height: min(height, size.height)
        )
    }
}
