//
//  PillStyles.swift
//  justscribe
//

import SwiftUI

// MARK: - Shared

/// Stroke color used around pill controls. `separatorColor` already adapts to
/// light/dark mode and is heavier than `.quaternaryLabelColor`, giving a
/// visible edge in both appearances.
private let pillStrokeColor = Color(nsColor: .separatorColor)
private let pillStrokeWidth: CGFloat = 1

// MARK: - Button

struct PillButtonStyle: ButtonStyle {
    enum Prominence {
        case primary
        case secondary
    }

    var prominence: Prominence = .secondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(background(pressed: configuration.isPressed))
                        .shadow(color: .black.opacity(0.08), radius: 1, y: 0.5)
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(strokeColor, lineWidth: pillStrokeWidth)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var strokeColor: Color {
        switch prominence {
        case .primary: return Color.accentColor.opacity(0.6)
        case .secondary: return pillStrokeColor
        }
    }

    private func background(pressed: Bool) -> Color {
        switch prominence {
        case .primary:
            return pressed ? Color.accentColor.opacity(0.85) : Color.accentColor
        case .secondary:
            return pressed
                ? Color(nsColor: .controlBackgroundColor).opacity(0.7)
                : Color(nsColor: .controlBackgroundColor)
        }
    }

    private var foreground: Color {
        switch prominence {
        case .primary: return .white
        case .secondary: return .primary
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static func pill(_ prominence: PillButtonStyle.Prominence) -> PillButtonStyle {
        PillButtonStyle(prominence: prominence)
    }
}

// MARK: - Pill background (for non-button surfaces like Menu labels)

struct PillBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.08), radius: 1, y: 0.5)
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(pillStrokeColor, lineWidth: pillStrokeWidth)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

extension View {
    func pillBackground() -> some View { modifier(PillBackground()) }
}

// MARK: - Toggle

struct PillToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        let isOn = configuration.isOn
        HStack(spacing: 8) {
            configuration.label
            switchTrack(isOn: isOn)
                .onTapGesture {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        configuration.isOn.toggle()
                    }
                }
        }
    }

    private func switchTrack(isOn: Bool) -> some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(isOn
                      ? Color.accentColor
                      : Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isOn ? Color.accentColor.opacity(0.7) : pillStrokeColor,
                                lineWidth: pillStrokeWidth)
                )

            Circle()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.18), radius: 1.5, y: 0.5)
                .padding(2)
        }
        .frame(width: 40, height: 24)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isOn)
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

extension ToggleStyle where Self == PillToggleStyle {
    static var pill: PillToggleStyle { PillToggleStyle() }
}
