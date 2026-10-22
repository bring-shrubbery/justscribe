import Foundation

public extension Array where Element == KeyboardAction {

    /// The standard callout actions for an action.
    ///
    /// These are the English actions for every locale.
    static func standardCalloutActions(
        for action: KeyboardAction,
        context: KeyboardContext
    ) -> [KeyboardAction]? {
        Callouts.Actions.english.actions(for: action)
    }
}

public extension Callouts.Actions {

    /// The standard callout actions for an action.
    static func standard(
        for action: KeyboardAction,
        context: KeyboardContext
    ) -> [KeyboardAction]? {
        .standardCalloutActions(for: action, context: context)
    }
}
