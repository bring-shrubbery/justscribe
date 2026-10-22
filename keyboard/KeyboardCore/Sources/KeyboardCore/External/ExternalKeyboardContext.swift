import SwiftUI

/// This context can be used to keep track of if an external
/// keyboard is connected to the device.
///
/// > Important: The Apple Smart Keyboard Folio keyboard can
/// be connected to a device without being actively used. It
/// should be fixed to only be considered connected when the
/// keyboard is actively being used.
public class ExternalKeyboardContext: ObservableObject {

    /// Create an external keyboard context.
    ///
    /// - Parameters:
    ///   - notificationCenter: The notification center to use.
    public init(
        notificationCenter: NotificationCenter = .default
    ) {
        self.notificationCenter = notificationCenter
    }

    /// The notification center to use for observations.
    public let notificationCenter: NotificationCenter

    /// Whether an external keyboard is connected.
    @Published var isExternalKeyboardConnected = false
}
