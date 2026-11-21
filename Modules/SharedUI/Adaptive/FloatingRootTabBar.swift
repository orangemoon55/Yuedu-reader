import SwiftUI
import UIKit

/// Geometry shared by the real controls and the layout tests. The bar never owns a
/// horizontal scroll view: on narrow widths it wraps into a second row instead of moving
/// under the user's finger. Artwork stays compact; each control keeps a 48pt hit frame.
struct FloatingRootTabBarLayout: Equatable {
    static let minimumHitSize: CGFloat = 48
    static let surfacePadding = DSSpacing.xs
    static let topSpacing = DSSpacing.xs
    static let bottomSpacing: CGFloat = 0
    static let defaultIconSize: CGFloat = 20
    static let compactHeight = DSLayout.minimumTapTarget + surfacePadding * 2
    static let maximumItemWidth: CGFloat = 80
    static let threeTabItemWidth: CGFloat = 82
    static let maximumWidth: CGFloat = 560
    static let hitExpansion: CGFloat = 6

    let itemWidth: CGFloat
    let capsuleWidth: CGFloat
    let searchDiameter: CGFloat
    let searchHitWidth: CGFloat
    let gap: CGFloat
    let contentWidth: CGFloat
    let viewportWidth: CGFloat
    let height: CGFloat
    let columns: Int
    let rows: Int
    let touchHeight: CGFloat
    let mainHeight: CGFloat
    let totalHeight: CGFloat

    init(availableWidth: CGFloat, mainTabCount: Int, hasSearch: Bool, height: CGFloat) {
        let count = max(0, mainTabCount)
        self.height = max(Self.compactHeight, height)
        searchDiameter = hasSearch ? Self.compactHeight : 0
        searchHitWidth = hasSearch ? searchDiameter + Self.hitExpansion * 2 : 0
        gap = count > 0 && hasSearch ? DSSpacing.sm : 0
        let padding = count > 0 ? Self.surfacePadding * 2 : 0
        let available = max(0, availableWidth.isFinite ? availableWidth : 0)
        let usable = max(0, min(available - DSSpacing.lg * 2, Self.maximumWidth))
        let mainSpace = max(0, usable - searchHitWidth - gap - padding)
        columns = count > 0 ? min(count, max(1, Int(mainSpace / Self.minimumHitSize))) : 0
        rows = columns > 0 ? (count + columns - 1) / columns : 0
        let itemLimit = count == 3 && columns == 3 ? Self.threeTabItemWidth : Self.maximumItemWidth
        itemWidth = columns > 0 ? max(Self.minimumHitSize, min(itemLimit, mainSpace / CGFloat(columns))) : 0
        capsuleWidth = columns > 0 ? CGFloat(columns) * itemWidth + padding : 0
        contentWidth = capsuleWidth + gap + searchHitWidth
        viewportWidth = contentWidth
        touchHeight = self.height + Self.hitExpansion * 2
        mainHeight = CGFloat(rows) * touchHeight + CGFloat(max(0, rows - 1)) * DSSpacing.xs
        totalHeight = max(mainHeight, searchHitWidth)
    }
}

/// A presentation of the existing TabView selection, never another navigation owner.
/// Search retains its own icon and route, but occupies the detached trailing circle.
struct FloatingRootTabBar: View {
    let tabs: [RootTabItem]
    @Binding var selection: RootTabItem
    var hidesLabels = false
    var iconSize: CGFloat = FloatingRootTabBarLayout.defaultIconSize
    var tint: Color = .accentColor
    var customIcon: (RootTabItem) -> RootTabRenderedIcon? = { _ in nil }
    /// Deterministic preview/testing input; nil follows the read-only system environment.
    var reduceTransparencyOverride: Bool? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionGlass
    @ScaledMetric(relativeTo: .caption) private var labelLineHeight: CGFloat = 15

    private var reduceTransparency: Bool { reduceTransparencyOverride ?? systemReduceTransparency }
    var mainTabs: [RootTabItem] { tabs.filter { $0 != .search } }
    var hasSearch: Bool { tabs.contains(.search) }
    private var drawnIconSize: CGFloat { RootTabIconRenderer.sanitizedIconSize(iconSize) }
    private var barHeight: CGFloat {
        let textHeight = hidesLabels || mainTabs.isEmpty ? 0
            : labelLineHeight * (dynamicTypeSize.isAccessibilitySize ? 2 : 1) + DSSpacing.xxs
        // Compact only at the default text size. Accessibility labels get two full
        // scaled lines and a taller capsule instead of shrinking their type or hit area.
        let contentHeight = max(FloatingRootTabBarLayout.minimumHitSize,
                                drawnIconSize + textHeight + DSSpacing.xs)
        return contentHeight + FloatingRootTabBarLayout.surfacePadding * 2
    }

    var body: some View {
        FloatingRootTabContentsLayout(mainCount: mainTabs.count, hasSearch: hasSearch, rowHeight: barHeight) {
            if !mainTabs.isEmpty {
                FloatingRootMainItemsLayout(rowHeight: barHeight + FloatingRootTabBarLayout.hitExpansion * 2) {
                    ForEach(mainTabs) { tab in
                        tabButton(tab, height: barHeight - FloatingRootTabBarLayout.surfacePadding * 2)
                    }
                }
                .padding(.horizontal, FloatingRootTabBarLayout.surfacePadding)
                .background { surface.padding(.vertical, FloatingRootTabBarLayout.hitExpansion).allowsHitTesting(false) }
            }
            if hasSearch { searchButton(diameter: FloatingRootTabBarLayout.compactHeight) }
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("rootTab.floatingBar")
    }

    private func tabButton(_ tab: RootTabItem, height: CGFloat) -> some View {
        Button { selection = tab } label: {
            VStack(spacing: DSSpacing.xxs) {
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
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background {
                if selection == tab {
                    ReadccGlassSelection(
                        shape: RoundedRectangle(cornerRadius: min(24, height / 2), style: .continuous),
                        tint: tint, reduceTransparencyOverride: reduceTransparency, samplesBackdrop: false
                    )
                    .matchedGeometryEffect(id: "selection-glass", in: selectionGlass)
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.88), value: selection)
            .padding(.vertical, FloatingRootTabBarLayout.surfacePadding + FloatingRootTabBarLayout.hitExpansion)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localized(tab.titleKey))
        .accessibilityAddTraits(selection == tab ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("rootTab.\(tab.rawValue)")
    }

    private func searchButton(diameter: CGFloat) -> some View {
        Button { selection = .search } label: {
            ZStack {
                surface
                if selection == .search {
                    ReadccGlassSelection(shape: Circle(), tint: tint,
                        reduceTransparencyOverride: reduceTransparency, samplesBackdrop: false).padding(5)
                        .matchedGeometryEffect(id: "selection-glass", in: selectionGlass)
                }
                // The original bitmap sits above, never inside, the selection wash.
                icon(for: .search).foregroundStyle(Color.primary)
            }
            .animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.88), value: selection)
            .frame(width: diameter, height: diameter)
            .padding(FloatingRootTabBarLayout.hitExpansion)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localized(RootTabItem.search.titleKey))
        .accessibilityAddTraits(selection == .search ? [.isButton, .isSelected] : [.isButton])
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
        NavigationGlassCapsule.selectionFill(tint: tint, scheme: colorScheme, contrast: contrast)
    }

    private var surface: some View {
        NavigationGlassCapsule(tint: tint, reduceTransparencyOverride: reduceTransparency)
    }

}

/// Pure layout: the width offered by the parent determines wrapping and total height.
/// No UIScreen geometry, state feedback, drag gesture, or scrolling viewport is involved.
private struct FloatingRootTabContentsLayout: Layout {
    let mainCount: Int
    let hasSearch: Bool
    let rowHeight: CGFloat

    private func layout(_ width: CGFloat) -> FloatingRootTabBarLayout {
        FloatingRootTabBarLayout(availableWidth: width, mainTabCount: mainCount, hasSearch: hasSearch, height: rowHeight)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(0, proposal.width ?? FloatingRootTabBarLayout.maximumWidth)
        return CGSize(width: width, height: layout(width).totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let geometry = layout(bounds.width)
        let x = bounds.minX + (bounds.width - geometry.contentWidth) / 2
        var index = 0
        if mainCount > 0, subviews.indices.contains(index) {
            subviews[index].place(at: CGPoint(x: x, y: bounds.midY - geometry.mainHeight / 2), anchor: .topLeading,
                                 proposal: ProposedViewSize(width: geometry.capsuleWidth, height: geometry.mainHeight))
            index += 1
        }
        if hasSearch, subviews.indices.contains(index) {
            subviews[index].place(at: CGPoint(x: x + geometry.capsuleWidth + geometry.gap,
                                             y: bounds.midY - geometry.searchHitWidth / 2), anchor: .topLeading,
                                 proposal: ProposedViewSize(width: geometry.searchHitWidth, height: geometry.searchHitWidth))
        }
    }
}

private struct FloatingRootMainItemsLayout: Layout {
    let rowHeight: CGFloat

    private func metrics(_ width: CGFloat, count: Int) -> (columns: Int, itemWidth: CGFloat, height: CGFloat) {
        guard count > 0 else { return (1, 0, 0) }
        let columns = min(count, max(1, Int(max(0, width) / FloatingRootTabBarLayout.minimumHitSize)))
        let rows = (count + columns - 1) / columns
        return (columns, width / CGFloat(columns), CGFloat(rows) * rowHeight + CGFloat(max(0, rows - 1)) * DSSpacing.xs)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(0, proposal.width ?? CGFloat(subviews.count) * FloatingRootTabBarLayout.maximumItemWidth)
        return CGSize(width: width, height: metrics(width, count: subviews.count).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let geometry = metrics(bounds.width, count: subviews.count)
        for index in subviews.indices {
            subviews[index].place(at: CGPoint(x: bounds.minX + CGFloat(index % geometry.columns) * geometry.itemWidth,
                                             y: bounds.minY + CGFloat(index / geometry.columns) * (rowHeight + DSSpacing.xs)),
                                 anchor: .topLeading,
                                 proposal: ProposedViewSize(width: geometry.itemWidth, height: rowHeight))
        }
    }
}
