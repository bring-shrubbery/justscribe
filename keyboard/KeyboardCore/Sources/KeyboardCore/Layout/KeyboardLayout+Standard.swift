import SwiftUI

public extension KeyboardLayout {

    /// The standard layout for the provided context.
    static func standard(
        for context: KeyboardContext
    ) -> KeyboardLayout {
        StandardLayoutService().keyboardLayout(for: context)
    }

    /// The layout adjusted for an input toolbar display mode.
    ///
    /// Layouts are not adjusted yet, so this returns the layout as is.
    func adjusted(
        for displayMode: Keyboard.InputToolbarDisplayMode,
        layoutConfiguration: KeyboardLayout.DeviceConfiguration
    ) -> KeyboardLayout {
        self
    }

    /// A layout with only the bottom row of this layout.
    var bottomRowLayout: KeyboardLayout {
        var layout = self
        layout.itemRows = layout.itemRows.suffix(1)
        return layout
    }

    /// Create an item with the layout's ideal height and insets.
    func createIdealItem(
        for action: KeyboardAction,
        width: KeyboardLayout.ItemWidth = .available,
        alignment: Alignment = .center
    ) -> KeyboardLayout.Item {
        .init(
            action: action,
            size: .init(width: width, height: idealItemHeight),
            alignment: alignment,
            edgeInsets: idealItemInsets
        )
    }
}
