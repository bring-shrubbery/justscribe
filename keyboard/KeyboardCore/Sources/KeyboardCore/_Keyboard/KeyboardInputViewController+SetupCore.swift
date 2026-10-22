#if os(iOS) || os(tvOS) || os(visionOS)
import SwiftUI

public extension KeyboardInputViewController {
    
    /// Set up KeyboardCore for the provided app.
    ///
    /// Call this in ``viewDidLoad()`` to make sure that the
    /// keyboard is properly configured as early as possible.
    ///
    /// See <doc:Getting-Started-Article> for information on
    /// how to properly set up an app and keyboard extension.
    ///
    /// - Parameters:
    ///   - app: The keyboard app to setup the controller for.
    ///   - completion: The function to call when the setup operation completes.
    func setup(
        for app: KeyboardApp,
        completion: @escaping (Result<Void, Error>) -> Void = { _ in }
    ) {
        setupController(for: app)
        completion(.success(()))
    }
}
#endif
