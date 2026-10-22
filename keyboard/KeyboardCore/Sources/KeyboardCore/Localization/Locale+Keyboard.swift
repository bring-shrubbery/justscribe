import Foundation

public extension Locale {

    /// Whether this locale prefers to replace alternate end
    /// quotation delimiters with begin ones.
    var prefersAlternateQuotationReplacement: Bool {
        if identifier.hasPrefix("en") { return false }
        return true
    }
}
