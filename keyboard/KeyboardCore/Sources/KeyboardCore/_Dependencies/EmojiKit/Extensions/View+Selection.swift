import SwiftUI

extension View {

    @ViewBuilder
    func selectionBackground(
        isSelected: Bool,
        cornerRadius: Double = 10
    ) -> some View {
        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
            self.background(selectionBackgroundShape(isSelected: isSelected))
                .containerShape(.rect(cornerRadius: cornerRadius))
        } else {
            self
        }
    }
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    func selectionBackgroundFillStyle(
        isSelected: Bool
    ) -> AnyShapeStyle {
        #if os(iOS) || os(macOS)
        switch isSelected {
        case true: .init(.selection)
        case false: .init(.clear)
        }
        #else
            .init(.clear)
        #endif
    }
    
    @ViewBuilder
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    func selectionBackgroundShape(
        isSelected: Bool
    ) -> some View {
        ContainerRelativeShape()
            .fill(selectionBackgroundFillStyle(isSelected: isSelected))
            .aspectRatio(1, contentMode: .fill)
    }
}
