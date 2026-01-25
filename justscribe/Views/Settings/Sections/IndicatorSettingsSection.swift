//
//  IndicatorSettingsSection.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import SwiftUI

struct IndicatorSettingsSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsSectionContainer(title: "Recording Indicator") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose how the transcription UI appears when activated.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    ForEach(IndicatorStyle.allCases, id: \.self) { style in
                        IndicatorStyleCard(
                            style: style,
                            isSelected: settings.indicatorStyle == style,
                            onSelect: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    settings.indicatorStyle = style
                                    // Sync with OverlayManager
                                    updateOverlayStyle(style)
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    private func updateOverlayStyle(_ style: IndicatorStyle) {
        Task { @MainActor in
            switch style {
            case .bubble:
                OverlayManager.shared.setStyle(.bubble)
            case .notch:
                OverlayManager.shared.setStyle(.notch)
            }
        }
    }
}

struct IndicatorStyleCard: View {
    let style: IndicatorStyle
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button {
            onSelect()
        } label: {
            VStack(spacing: 12) {
                // Preview illustration
                previewIllustration
                    .frame(height: 60)

                VStack(spacing: 4) {
                    Text(style.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(styleDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var styleDescription: String {
        switch style {
        case .bubble:
            return "Floating pill at bottom of screen"
        case .notch:
            return "Expands from MacBook notch"
        }
    }

    @ViewBuilder
    private var previewIllustration: some View {
        switch style {
        case .bubble:
            VStack {
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 40, height: 6)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(Capsule())
                .shadow(radius: 2)
            }

        case .notch:
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    // Notch shape
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 30, height: 4)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 12,
                            bottomTrailingRadius: 12,
                            topTrailingRadius: 0
                        )
                    )
                    Spacer()
                }
                Spacer()
            }
        }
    }
}
