import SwiftUI

/// Each real category gets its own target; a long catalogue scrolls instead of shrinking.
struct DiscoveryCategoryBar: View {
    let catalog: [DiscoveryCategoryChoice]
    let selection: ExploreCategoryReference?
    let select: (ExploreCategoryReference) -> Void
    @ScaledMetric(relativeTo: .subheadline) private var chipHeight: CGFloat = DSLayout.minimumTapTarget
    private var viewportHeight: CGFloat { max(DSLayout.minimumTapTarget, chipHeight) + DSSpacing.xs * 2 }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: DSSpacing.xs) {
                    ForEach(catalog, id: \.reference) { category in
                        let selected = category.reference == selection
                        Button { select(category.reference) } label: {
                            DSCapsuleLabel(title: category.title, isSelected: selected, onCard: true,
                                           minWidth: DSLayout.minimumTapTarget)
                                .frame(minHeight: max(DSLayout.minimumTapTarget, chipHeight))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .id(category.reference)
                    }
                }
                .padding(.horizontal, DSSpacing.xs)
                .frame(height: viewportHeight)
            }
            .contentMargins(.vertical, 0, for: .scrollContent)
            .contentMargins(.vertical, 0, for: .scrollIndicators)
            .frame(height: viewportHeight)
            .clipShape(Capsule())
            .scrollIndicators(.hidden)
            .background { NavigationGlassCapsule(tint: DSColor.accent) }
            .accessibilityIdentifier("discovery.category.bar")
            .onChange(of: selection, initial: true) { _, reference in
                if let reference { proxy.scrollTo(reference) }
            }
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.top, DSSpacing.xs)
        .padding(.bottom, DSSpacing.xxs)
    }
}

/// Pick the owner of the entire Search feed, before selecting any of its categories.
struct DiscoverySearchSourcePicker: View {
    let sources: [BookSource]
    let selectedURL: String?
    let choose: (BookSource) -> Void
    let close: () -> Void
    var body: some View {
        AdaptiveSheetContainer(maxWidth: DSLayout.readableCompactWidth) {
            NavigationStack {
                DiscoverySourcePickerList(sources: sources, selectedURL: selectedURL,
                                          choose: choose, close: close)
            }
        }
    }
}
