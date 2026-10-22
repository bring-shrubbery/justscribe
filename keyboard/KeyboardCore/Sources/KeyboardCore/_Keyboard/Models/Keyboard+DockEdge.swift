import SwiftUI

public extension Keyboard {
    
    /// This enum defines supported keyboard dock edges.
    ///
    /// You can apply a custom value using the view modifier
    /// ``SwiftUICore/View/keyboardDockEdge(_:)``.
    enum DockEdge: String, Identifiable, CaseIterable, KeyboardModel {
        
        /// Dock the keyboard to the leading edge.
        case leading
        
        /// Dock the keyboard to the trailing edge.
        case trailing
    }
}

public extension Keyboard.DockEdge {
    
    /// The unique edge ID.
    var id: String { rawValue }
    
    /// The corresponding keyboard alignment.
    var alignment: Alignment {
        switch self {
        case .leading: .leading
        case .trailing: .trailing
        }
    }
    
    /// The corresponding horizontal edge.
    var edge: HorizontalEdge {
        switch self {
        case .leading: .leading
        case .trailing: .trailing
        }
    }
}

public extension View {

    /// Apply a ``Keyboard/DockEdge`` value.
    func keyboardDockEdge(
        _ value: Keyboard.DockEdge?
    ) -> some View {
        self.environment(\.keyboardDockEdge, value)
    }
}

public extension EnvironmentValues {

    /// Apply a ``Keyboard/DockEdge`` value.
    @Entry var keyboardDockEdge: Keyboard.DockEdge?
}
