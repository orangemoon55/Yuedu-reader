import SwiftUI
import UIKit

/// Geometry shared by the real controls and the layout tests. Never shrink a touch
/// target below 44pt; an unusually narrow container scrolls instead of clipping it.
struct FloatingRootTabBarLayout: Equatable {
    static let minimumHitSize: CGFloat = 44
    static let surfacePadding: CGFloat = 6
    static let bottomSpacing: CGFloat = 8
    static let topSpacing: CGFloat = 8

    let itemWidth: CGFloat
    let capsuleWidth: CGFloat
    let searchDiameter: CGFloat
    let gap: CGFloat
    let contentWidth: CGFloat
    let viewportWidth: CGFloat
    let height: CGFloat

    init(availableWidth: CGFloat, mainTabCount: Int, hasSearch: Bool, height: CGFloat) {
        let count = max(0, mainTabCount)
        self.height = max(Self.minimumHitSize + Self.surfacePadding * 2, height)
        searchDiameter = hasSearch ? min(self.height, 68) : 0
        gap = count > 0 && hasSearch ? 10 : 0
        let padding = count > 0 ? Self.surfacePadding * 2 : 0
        let available = max(0, availableWidth.isFinite ? availableWidth : 0)
        let usable = max(0, min(available - 24, 620))
        let candidate = count > 0 ? (usable - searchDiameter - gap - padding) / CGFloat(count) : 0
        itemWidth = count > 0 ? max(Self.minimumHitSize, min(104, candidate)) : 0
        capsuleWidth = CGFloat(count) * itemWidth + padding
        contentWidth = capsuleWidth + gap + searchDiameter
        viewportWidth = min(available, contentWidth)
    }
}

/// A presentation of the existing TabView selection, never another navigation owner.
/// Search retains its own icon and route, but occupies the detached trailing circle.
struct FloatingRootTabBar: View {
    let tabs: [RootTabItem]
    @Binding var selection: RootTabItem
    var hidesLabels = false
    var iconSize: CGFloat = 28
    var tint: Color = .accentColor
    var customIcon: (RootTabItem) -> RootTabRenderedIcon? = { _ in nil }
    /// Deterministic preview/testing input; nil follows the read-only system environment.
    var reduceTransparencyOverride: Bool? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.accessibilityContrast) private var contrast
    @ScaledMetric(relativeTo: .caption) private var labelLineHeight: CGFloat = 15

    private var reduceTransparency: Bool { reduceTransparencyOverride ?? systemReduceTransparency }
    var mainTabs: [RootTabItem] { tabs.filter { $0 != .search } }
    var hasSearch: Bool { tabs.contains(.search) }
    private var drawnIconSize: CGFloat { RootTabIconRenderer.sanitizedIconSize(iconSize) }
    private var barHeight: CGFloat {
        let textHeight = hidesLabels || mainTabs.isEmpty ? 0
            : labelLineHeight * (dynamicTypeSize.isAccessibilitySize ? 2 : 1) + 3
        return max(64, drawnIconSize + textHeight + 16)
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = FloatingRootTabBarLayout(
                availableWidth: geometry.size.width, mainTabCount: mainTabs.count,
                hasSearch: hasSearch, height: barHeight
            )
            ScrollView(.horizontal) {
                HStack(spacing: layout.gap) {
                    if !mainTabs.isEmpty {
                        HStack(spacing: 0) {
                            ForEach(mainTabs) { tab in
                                tabButton(tab, width: layout.itemWidth, height: layout.height - 12)
                            }
                        }
                        .padding(FloatingRootTabBarLayout.surfacePadding)
                        .background { surface }
                    }
                    if hasSearch {
                        searchButton(diameter: layout.searchDiameter)
                    }
                }
                .frame(width: layout.contentWidth, height: layout.height)
                // Shadow room does not consume a button's hit area.
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled(layout.contentWidth <= layout.viewportWidth)
            .scrollBounceBehavior(.basedOnSize)
            .frame(width: layout.viewportWidth, height: layout.height + 12)
            .frame(maxWidth: .infinity)
            .offset(y: -6)
        }
        .frame(height: barHeight)
        .accessibilityIdentifier("rootTab.floatingBar")
    }

    private func tabButton(_ tab: RootTabItem, width: CGFloat, height: CGFloat) -> some View {
        Button { selection = tab } label: {
            VStack(spacing: 3) {
                icon(for: tab)
                if !hidesLabels {
                    Text(localized(tab.titleKey))
                        .font(DSFont.caption.weight(.semibold))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 3)
            .frame(width: width, height: height)
            .background {
                if selection == tab {
                    RoundedRectangle(cornerRadius: min(24, height / 2), style: .continuous)
                        .fill(selectionFill)
                        .overlay {
                            RoundedRectangle(cornerRadius: min(24, height / 2), style: .continuous)
                                .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.5 : 0.06))
                        }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localized(tab.titleKey))
        .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
        .accessibilityIdentifier("rootTab.\(tab.rawValue)")
    }

    private func searchButton(diameter: CGFloat) -> some View {
        Button { selection = .search } label: {
            ZStack {
                surface
                if selection == .search {
                    Circle().fill(selectionFill).padding(5)
                }
                // The original bitmap sits above, never inside, the selection wash.
                icon(for: .search).foregroundStyle(Color.primary)
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localized(RootTabItem.search.titleKey))
        .accessibilityAddTraits(selection == .search ? [.isSelected] : [])
        .accessibilityIdentifier("rootTab.search")
    }

    @ViewBuilder
    private func icon(for tab: RootTabItem) -> some View {
        if let rendered = customIcon(tab) {
            Image(uiImage: rendered.image)
                .renderingMode(rendered.isTemplate ? .template : .original)
                .resizable()
                .scaledToFit()
                .frame(width: drawnIconSize, height: drawnIconSize)
        } else {
            Image(systemName: tab.defaultSystemImage)
                .font(.system(size: drawnIconSize, weight: .regular))
                .frame(width: drawnIconSize, height: drawnIconSize)
        }
    }

    private var selectionFill: Color {
        tint.opacity(contrast == .increased ? 0.28 : (colorScheme == .dark ? 0.22 : 0.12))
    }

    private var surface: some View {
        Capsule(style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                Capsule(style: .continuous)
                    .fill(reduceTransparency ? Color(uiColor: .secondarySystemBackground)
                          : Color(red: 0.83, green: 0.77, blue: 0.68).opacity(colorScheme == .dark ? 0.04 : 0.12))
            }
            .overlay { Capsule(style: .continuous).fill(tint.opacity(reduceTransparency ? 0.04 : 0.035)) }
            .overlay {
                Capsule(style: .continuous).strokeBorder(
                    Color.white.opacity(contrast == .increased ? 0.65 : (colorScheme == .dark ? 0.16 : 0.55)),
                    lineWidth: contrast == .increased ? 1.5 : 0.75
                )
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.12), radius: 12, y: 5)
    }
}
