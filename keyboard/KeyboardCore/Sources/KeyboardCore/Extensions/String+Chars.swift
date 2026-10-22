import Foundation

public extension String {

    /// Split the string into a list of characters.
    var chars: [String] { map(String.init) }

    /// Split the string into a list of character actions.
    var charActions: [KeyboardAction] {
        charActions(removeSpaces: false)
    }

    /// Split the string into a list of character actions.
    func charActions(
        removeSpaces: Bool
    ) -> [KeyboardAction] {
        let chars = removeSpaces ? chars.filter { $0 != " " } : chars
        return chars.map(KeyboardAction.character)
    }
}
