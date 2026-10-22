import CoreGraphics
import SwiftUI

/// This type defines the full set of keys on a keyboard and
/// is also a namespace for layout-related types.
///
/// A layout also specifies sizes, alignments, etc. which is
/// required information when rendering a keyboard.
///
/// You can use the ``itemRows`` property to modify a layout,
/// e.g. with the various insert, replace & remove functions.
public struct KeyboardLayout {

    /// Create a new layout with the provided items.
    public init(
        itemRows rows: ItemRows,
        deviceConfiguration: DeviceConfiguration? = nil,
        iPadProLayout: Bool = false,
        idealItemHeight height: Double? = nil,
        idealItemInsets insets: EdgeInsets? = nil,
        inputToolbarInputSet: InputSet? = nil
    ) {
        self.itemRows = rows
        self.deviceConfiguration = deviceConfiguration
        self.isIpadProLayout = iPadProLayout
        self.idealItemHeight = height ?? Self.resolveIdealItemHeight(for: rows)
        self.idealItemInsets = insets ?? Self.resolveIdealItemInsets(for: rows)
        self.inputToolbarInputSet = inputToolbarInputSet
    }

    /// The device configuration for the layout.
    ///
    /// TODO: This will be non-optional in KeyboardCore 10.
    public var deviceConfiguration: DeviceConfiguration?

    /// The layout item rows to show in the keyboard.
    public var itemRows: ItemRows

    /// The ideal item height.
    public var idealItemHeight: Double

    /// The ideal item inserts.
    public var idealItemInsets: EdgeInsets
    
    public var isIpadProLayout: Bool

    /// The input set to use for a top input toolbar.
    public var inputToolbarInputSet: InputSet?

    /// A `CGFloat` typealias for the total keyboard width.
    public typealias TotalWidth = CGFloat

    /// A cache used to avoid having to recalculate widths.
    var widthCache = WidthCache()
}

extension KeyboardLayout {

    class WidthCache {

        var data = [TotalWidth: CGFloat]()
    }
}

private extension KeyboardLayout {

    static func resolveIdealItemHeight(
        for rows: KeyboardLayout.ItemRows
    ) -> Double {
        let item = rows.flatMap { $0 }.first
        return Double(item?.size.height ?? .zero)
    }

    static func resolveIdealItemInsets(
        for rows: KeyboardLayout.ItemRows
    ) -> EdgeInsets {
        let item = rows.flatMap { $0 }.first
        return item?.edgeInsets ?? EdgeInsets()
    }
}

public extension KeyboardLayout {

    @available(*, deprecated, message: "Just use init injection instead.")
    typealias LayoutBuilder = (LayoutBuilderParams) -> KeyboardLayout?

    @available(*, deprecated, message: "Just use init injection instead.")
    struct LayoutBuilderParams: KeyboardModel {

        /// Create a layout builder parameter value.
        public init() {}

        /// Get the standard layout for the context.
        public func standardLayout(
            for context: KeyboardContext
        ) -> KeyboardLayout {
            .standard(for: context)
        }
    }
}

public extension EnvironmentValues {

    @available(*, deprecated, message: "Just use init injection instead.")
    @Entry var keyboardLayoutBuilder: KeyboardLayout.LayoutBuilder = { _ in nil }
}
