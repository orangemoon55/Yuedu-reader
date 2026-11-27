import SwiftUI

/// Cards that scale up on hover, scale down on press, with a soft shadow.
struct InteractiveCardStyle: ButtonStyle {
    var showShadow = true
    var hoverScale: CGFloat = 1.02
    var pressScale: CGFloat = 0.98

    #if os(macOS)
    @State private var isHovering = false
    #endif

    func makeBody(configuration: Configuration) -> some View {
        #if os(macOS)
        configuration.label
            .scaleEffect(configuration.isPressed ? pressScale : (isHovering ? hoverScale : 1.0))
            .shadow(
                color: showShadow && isHovering ? .black.opacity(0.15) : .clear,
                radius: isHovering ? 12 : 0,
                x: 0,
                y: isHovering ? 4 : 0
            )
            .animation(AppAnimation.spring, value: configuration.isPressed)
            .animation(AppAnimation.spring, value: isHovering)
            .scrollAwareHover { isHovering = $0 }
        #else
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1.0)
        #endif
    }
}

/// List rows with a hover background highlight.
struct InteractiveRowStyle: ButtonStyle {
    var cornerRadius: CGFloat = Theme.Radius.standard
    var hoverColor: Color = .primary.opacity(0.06)

    #if os(macOS)
    @State private var isHovering = false
    #endif

    func makeBody(configuration: Configuration) -> some View {
        #if os(macOS)
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isHovering || configuration.isPressed ? hoverColor : .clear)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(AppAnimation.quick, value: configuration.isPressed)
            .animation(AppAnimation.quick, value: isHovering)
            .scrollAwareHover { isHovering = $0 }
        #else
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(configuration.isPressed ? hoverColor : .clear)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(AppAnimation.quick, value: configuration.isPressed)
        #endif
    }
}

/// Subtle press feedback for icon buttons.
struct PressableButtonStyle: ButtonStyle {
    var pressScale: CGFloat = 0.9
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressScale : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(reduceMotion ? nil : AppAnimation.quick, value: configuration.isPressed)
    }
}

/// Filter chips (category pickers).
struct ChipButtonStyle: ButtonStyle {
    var isSelected: Bool

    #if os(macOS)
    @State private var isHovering = false
    #endif

    func makeBody(configuration: Configuration) -> some View {
        #if os(macOS)
        configuration.label
            .font(Theme.Typography.secondary.weight(isSelected ? .semibold : .medium))
            .padding(.horizontal, Theme.Spacing.control)
            .padding(.vertical, Theme.Spacing.small)
            .background(
                Capsule().fill(
                    isSelected
                        ? AnyShapeStyle(Theme.accent)
                        : AnyShapeStyle(.primary.opacity(isHovering ? 0.1 : 0.06))
                )
            )
            .foregroundStyle(isSelected ? .white : .primary)
            .scaleEffect(configuration.isPressed ? 0.95 : (isHovering ? 1.03 : 1.0))
            .animation(AppAnimation.spring, value: configuration.isPressed)
            .animation(AppAnimation.spring, value: isHovering)
            .scrollAwareHover { isHovering = $0 }
        #else
        configuration.label
            .font(Theme.Typography.secondary.weight(isSelected ? .semibold : .medium))
            .padding(.horizontal, Theme.Spacing.control)
            .padding(.vertical, Theme.Spacing.small)
            .background(
                Capsule().fill(
                    isSelected
                        ? AnyShapeStyle(Theme.accent)
                        : AnyShapeStyle(.primary.opacity(0.06))
                )
            )
            .foregroundStyle(isSelected ? .white : .primary)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(AppAnimation.spring, value: configuration.isPressed)
        #endif
    }
}

extension ButtonStyle where Self == InteractiveCardStyle {
    static var interactiveCard: InteractiveCardStyle { InteractiveCardStyle() }
}

extension ButtonStyle where Self == InteractiveRowStyle {
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

extension ButtonStyle where Self == ChipButtonStyle {
    static func chip(isSelected: Bool) -> ChipButtonStyle { ChipButtonStyle(isSelected: isSelected) }
}


/// Shared symbol changes, with the same meaning on the iPadOS 16 fallback.
struct PlayerSymbolTransition: ViewModifier {
    let symbol: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            content
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace, options: .speed(1.6)))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: symbol)
        } else {
            content
                .contentTransition(reduceMotion ? .identity : .opacity)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: symbol)
        }
    }
}

/// Only explicit user feedback advances this trigger; mounting a row never bounces.
struct PlayerSymbolBounce: ViewModifier {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fallbackScale: CGFloat = 1
    @State private var fallbackTask: Task<Void, Never>?

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            content
                .symbolEffect(.bounce, options: .speed(1.3), value: trigger)
                .symbolEffectsRemoved(reduceMotion)
        } else {
            content
                .scaleEffect(reduceMotion ? 1 : fallbackScale)
                .onChange(of: trigger) { _ in
                    fallbackTask?.cancel()
                    guard !reduceMotion else { fallbackScale = 1; return }
                    fallbackTask = Task { @MainActor in
                        withAnimation(.easeOut(duration: 0.1)) { fallbackScale = 1.12 }
                        do { try await Task.sleep(for: .milliseconds(100)) }
                        catch { return }
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.6)) { fallbackScale = 1 }
                    }
                }
                .onDisappear {
                    fallbackTask?.cancel()
                    fallbackTask = nil
                    fallbackScale = 1
                }
        }
    }
}

/// Feedback lives inside the existing hit area, so controls do not move or resize.
struct PlayerTransportButtonStyle: ButtonStyle {
    var diameter: CGFloat = 44
    var tint: Color = .primary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1)
            .background {
                Circle()
                    .fill(tint.opacity(configuration.isPressed ? 0.1 : 0))
                    .frame(width: diameter, height: diameter)
                    .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: configuration.isPressed ? 0.1 : 0.24),
                       value: configuration.isPressed)
    }
}
