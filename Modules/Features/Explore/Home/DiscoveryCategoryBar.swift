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
    @State private var query = ""
    // Reuse the old picker UUID preferences, not the book-source content/sync order.
    @State private var pins = DiscoverySourcePins()

    private var results: [BookSource] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return pins.orderedBookSources(sources.filter {
            term.isEmpty || $0.bookSourceName.localizedStandardContains(term)
                || $0.bookSourceUrl.localizedStandardContains(term)
        })
    }

    var body: some View {
        AdaptiveSheetContainer(maxWidth: DSLayout.readableCompactWidth) {
            NavigationStack {
                List {
                    Section {
                        ForEach(results) { source in
                            let selected = source.bookSourceUrl == selectedURL
                            Button { choose(source) } label: {
                                HStack {
                                    if pins.isPinned(source.id) {
                                        Image(systemName: "pin.fill")
                                            .foregroundStyle(DSColor.accent)
                                            .accessibilityHidden(true)
                                    }
                                    Text(BookSourceDisplayName.title(source.bookSourceName))
                                    Spacer()
                                    if selected {
                                        Image(systemName: "checkmark").accessibilityHidden(true)
                                    }
                                }
                                .foregroundStyle(DSColor.textPrimary)
                            }
                            .accessibilityAddTraits(selected ? [.isSelected] : [])
                            .accessibilityIdentifier("discovery.source.choose.\(source.bookSourceUrl)")
                            .accessibilityValue(pins.isPinned(source.id) ? localized("已置頂") : "")
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    pins.togglePin(source.id, availableIDs: Set(sources.map(\.id)))
                                } label: {
                                    Label(localized(pins.isPinned(source.id) ? "取消置頂" : "置頂"),
                                          systemImage: pins.isPinned(source.id) ? "pin.slash" : "pin")
                                }
                                .tint(DSColor.accent)
                            }
                        }
                    }
                    .interfaceSectionSurface()
                }
                .navigationTitle(localized("來源配置"))
                .navigationBarTitleDisplayMode(.inline)
                .themedAppSurface(for: .explore)
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                            prompt: localized("搜尋來源配置名稱或網址"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(localized("關閉"), action: close)
                            .accessibilityIdentifier("discovery.source.close")
                    }
                }
            }
        }
    }
}
