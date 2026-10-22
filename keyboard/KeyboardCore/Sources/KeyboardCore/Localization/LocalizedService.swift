import Foundation

/// This protocol is implemented by locale-specific services.
///
/// The protocol simplifies aggregating services and resolve
/// a service instance for a certain locale.
public protocol LocalizedService {
    
    /// The unique locale key to use when looking up values.
    var localeKey: String { get }
}
