//
//  NotchContentView.swift
//  DynamicNotchKit
//
//  Created by Kai Azim on 2025-04-19.
//

import Combine
import SwiftUI

struct NotchContentView<Expanded, CompactLeading, CompactTrailing>: View where Expanded: View, CompactLeading: View, CompactTrailing: View {
    @ObservedObject private var dynamicNotch: DynamicNotch<Expanded, CompactLeading, CompactTrailing>
    @Namespace private var namespace
    private let style: DynamicNotchStyle

    init(dynamicNotch: DynamicNotch<Expanded, CompactLeading, CompactTrailing>, style: DynamicNotchStyle) {
        self.dynamicNotch = dynamicNotch
        self.style = style
    }

    // Vendored change (JustScribe): no drop shadow around the expanded notch.

    var body: some View {
        ZStack {
            if style.isNotch {
                NotchView(dynamicNotch: dynamicNotch)
                    .foregroundStyle(.white)
            } else {
                NotchlessView(dynamicNotch: dynamicNotch)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.notchStyle, style)
        .animation(.snappy(duration: 0.4), value: dynamicNotch.isHovering)
        .onAppear {
            if dynamicNotch.namespace == nil {
                dynamicNotch.namespace = namespace
            }
        }
    }
}
