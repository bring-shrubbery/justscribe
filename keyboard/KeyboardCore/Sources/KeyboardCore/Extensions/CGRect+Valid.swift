import CoreGraphics

extension CGRect {
    
    /// Check if the rect is valid for being drawn in a path.
    var isValidForPath: Bool { !width.isNaN && !height.isNaN }
}
