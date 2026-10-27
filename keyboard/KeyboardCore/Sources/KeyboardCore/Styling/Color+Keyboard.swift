import SwiftUI

public extension Color {

    /// This color can be used instead of `clear` to make it
    /// register touches & gestures.
    static var clearInteractable: Self {
        Color.white.opacity(0.001)
    }

    /// The standard keyboard background color.
    static let keyboardBackground = Color("keyboardBackground", bundle: .keyboardCore)

    /// The standard keyboard background color for dark appearance.
    static let keyboardBackgroundForDarkAppearance = Color("keyboardBackgroundForDarkAppearance", bundle: .keyboardCore)

    /// The standard keyboard button background color.
    static let keyboardButtonBackground = Color("keyboardButtonBackground", bundle: .keyboardCore)

    /// The standard keyboard button background color, adjusted for the iOS color scheme bug.
    static let keyboardButtonBackgroundForColorSchemeBug = Color("keyboardButtonBackgroundForColorSchemeBug", bundle: .keyboardCore)

    /// The standard keyboard button background color for dark appearance.
    static let keyboardButtonBackgroundForDarkAppearance = Color("keyboardButtonBackgroundForDarkAppearance", bundle: .keyboardCore)

    /// The standard keyboard button foreground color.
    static let keyboardButtonForeground = Color("keyboardButtonForeground", bundle: .keyboardCore)

    /// The standard keyboard button foreground color for dark appearance.
    static let keyboardButtonForegroundForDarkAppearance = Color("keyboardButtonForegroundForDarkAppearance", bundle: .keyboardCore)

    /// The standard keyboard button shadow color.
    static let keyboardButtonShadow = Color("keyboardButtonShadow", bundle: .keyboardCore)

    /// The standard dark keyboard button background color.
    static let keyboardDarkButtonBackground = Color("keyboardDarkButtonBackground", bundle: .keyboardCore)

    /// The standard dark keyboard button background color for the iOS color scheme bug.
    static let keyboardDarkButtonBackgroundForColorSchemeBug = Color("keyboardDarkButtonBackgroundForColorSchemeBug", bundle: .keyboardCore)

    /// The standard dark keyboard button background color for dark apperance.
    static let keyboardDarkButtonBackgroundForDarkAppearance = Color("keyboardDarkButtonBackgroundForDarkAppearance", bundle: .keyboardCore)

    /// The standard dark keyboard button foreground color.
    static var keyboardDarkButtonForeground: Self {
        Color("keyboardButtonForeground", bundle: .keyboardCore)
    }
    
    /// The standard dark keyboard button foreground color for dark apperance.
    static var keyboardDarkButtonForegroundForDarkAppearance: Self {
        Color("keyboardButtonForegroundForDarkAppearance", bundle: .keyboardCore)
    }
}

// MARK: - Contextual Colors

public extension Color {
    
    /// The standard keyboard button background color.
    static func keyboardBackground(
        for colorScheme: ColorScheme
    ) -> Self {
        .keyboardBackground
    }

    /// The standard keyboard button background color.
    static func keyboardButtonBackground(
        for colorScheme: ColorScheme
    ) -> Self {
        colorScheme.isDark ?
            .keyboardButtonBackgroundForColorSchemeBug :
            .keyboardButtonBackground
    }

    /// The standard keyboard button background color.
    ///
    /// This color is adjusted for display with Liquid Glass.
    static func keyboardButtonBackgroundLiquid(
        for colorScheme: ColorScheme
    ) -> Self {
        return colorScheme.isDark ?
            .keyboardButtonBackgroundForColorSchemeBug.opacity(0.55) :
            .keyboardButtonBackground
    }

    /// The standard keyboard button foreground color.
    static func keyboardButtonForeground(
        for colorScheme: ColorScheme
    ) -> Self {
        colorScheme.isDark ?
            .keyboardButtonForegroundForDarkAppearance :
            .keyboardButtonForeground
    }

    /// The standard keyboard button shadow color.
    static func keyboardButtonShadow(
        for colorScheme: ColorScheme
    ) -> Self {
        .keyboardButtonShadow
    }

    /// The standard dark keyboard button background color.
    static func keyboardDarkButtonBackground(
        for colorScheme: ColorScheme
    ) -> Self {
        colorScheme.isDark ?
            .keyboardDarkButtonBackgroundForColorSchemeBug :
            .keyboardDarkButtonBackground
    }

    /// The standard dark keyboard button foreground color.
    static func keyboardDarkButtonForeground(
        for colorScheme: ColorScheme
    ) -> Self {
        colorScheme.isDark ?
            .keyboardDarkButtonForegroundForDarkAppearance :
            .keyboardDarkButtonForeground
    }
}

private extension ColorScheme {
    
    var isDark: Bool {
        self == .dark
    }
}

#Preview {

    return ScrollView(.vertical) {
        VStack(spacing: 40) {
            StylePreviewHeader(title: "Colors")

            LazyVGrid(columns: .preview, spacing: 20) {
                preview(for: .keyboardBackground, "keyboardBackground")
                preview(for: .keyboardBackgroundForDarkAppearance, "keyboardBackgroundForDarkAppearance")
                preview(for: .keyboardButtonBackground, "keyboardButtonBackground")
                preview(for: .keyboardButtonBackgroundForColorSchemeBug, "keyboardButtonBackgroundForColorSchemeBug")
                preview(for: .keyboardButtonBackgroundForDarkAppearance, "keyboardButtonBackgroundForDarkAppearance")
                preview(for: .keyboardButtonForeground, "keyboardButtonForeground")
                preview(for: .keyboardButtonForegroundForDarkAppearance, "keyboardButtonForegroundForDarkAppearance")
                preview(for: .keyboardButtonShadow, "keyboardButtonShadow")
                preview(for: .keyboardDarkButtonBackground, "keyboardDarkButtonBackground")
                preview(for: .keyboardDarkButtonBackgroundForColorSchemeBug, "keyboardDarkButtonBackgroundForColorSchemeBug")
                preview(for: .keyboardDarkButtonBackgroundForDarkAppearance, "keyboardDarkButtonBackgroundForDarkAppearance")
                preview(for: .keyboardDarkButtonForeground, "keyboardDarkButtonForeground")
                preview(for: .keyboardDarkButtonForegroundForDarkAppearance, "keyboardDarkButtonForegroundForDarkAppearance")
            }
        }
        .padding()
        .font(.title.weight(.regular))
    }

    func preview(for color: Color, _ name: String) -> some View {
        Button {
            print(name)
        } label: {
            HStack(spacing: 0) {
                color
                color.colorScheme(.dark)
            }
        }
        .background(Color.keyboardBackground)
        .aspectRatio(1, contentMode: .fill)
        .cornerRadius(10)
        .shadow(radius: 1, y: 1)
    }
}

struct StylePreviewHeader: View {

    let title: String

    var body: some View {
        VStack {
            Text(title)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.keyboardBackground)
        .clipShape(.rect(cornerRadius: 5))
        .shadow(radius: 1, y: 1)
    }
}

private extension Array where Element == GridItem {

    static var preview: Self {
        [.init(.adaptive(minimum: 100, maximum: 120), spacing: 20)]
    }
}
