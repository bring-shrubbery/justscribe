import SwiftUI

extension Keyboard {
    
    /// This view is used as a wrapper view, to make sure it
    /// binds to state that affects your layout.
    struct RootView<ViewType: View>: View {
        
        init(@ViewBuilder _ view: @escaping () -> ViewType) {
            self.view = view
        }
        
        var view: () -> ViewType
    
        @EnvironmentObject var autocompleteContext: AutocompleteContext
        @EnvironmentObject var externalContext: ExternalKeyboardContext
        @EnvironmentObject var keyboardContext: KeyboardContext

        var body: some View {
            view()
                .keyboardDockEdge(keyboardContext.settings.keyboardDockEdge)
                .onChange(of: externalContext.isExternalKeyboardConnected) { newValue in
                    guard keyboardContext.settings.isKeyboardAutoCollapseEnabled else { return }
                    keyboardContext.isKeyboardCollapsed = newValue
                }
        }
    }
}
