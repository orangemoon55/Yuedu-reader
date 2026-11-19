import SwiftUI

/// The five category cells share the bottom bar's glass surface but keep independent hit areas.
struct DiscoveryCategoryBar: View {
    let slots: DiscoveryCategorySlots
    let selection: Int
    let select: (Int) -> Void
    let edit: (Int) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 0) {
            ForEach(slots.choices.indices.filter { slots.choices[$0] != nil }, id: \.self) { index in
                let choice = slots.choices[index]
                let selected = selection == index
                Button { select(index) } label: {
                    Text(choice?.title ?? String(format: localized("分類 %d"), index + 1))
                        .font((typeSize.isAccessibilitySize ? DSFont.caption : DSFont.subheadline).weight(.semibold))
                        .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                        .minimumScaleFactor(0.80)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 3)
                        .padding(.vertical, DSSpacing.xs)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: typeSize.isAccessibilitySize ? 64 : DSLayout.minimumTapTarget)
                        .background {
                            if selected {
                                Capsule(style: .continuous)
                                    .fill(NavigationGlassCapsule.selectionFill(tint: DSColor.accent, scheme: scheme, contrast: contrast))
                                    .overlay {
                                        Capsule(style: .continuous)
                                            .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.5 : 0.06))
                                    }
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .accessibilityIdentifier("discovery.category.slot.\(index)")
                .contextMenu {
                    Button { edit(index) } label: {
                        Label(localized("更換分類"), systemImage: "square.grid.2x2")
                    }
                }
            }
        }
        .padding(DSSpacing.xs)
        .background { NavigationGlassCapsule(tint: DSColor.accent) }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.sm)
        .accessibilityIdentifier("discovery.category.bar")
    }
}

/// Customize a shortcut without leaving the selected source's real catalog.
struct DiscoverySlotSettings: View {
    let slots: DiscoveryCategorySlots
    let catalog: [DiscoveryCategoryChoice]
    let openSlot: Int?
    let choose: (DiscoveryCategoryChoice, Int) -> Void
    let close: () -> Void

    @State private var opened: Int?

    var body: some View {
        AdaptiveSheetContainer(maxWidth: DSLayout.readableCompactWidth) {
            NavigationStack {
                List {
                    Section {
                        ForEach(slots.choices.indices, id: \.self) { index in
                            let title = String(format: localized("分類 %d"), index + 1)
                            Button { opened = index } label: {
                                HStack {
                                    Text(title).foregroundStyle(DSColor.textPrimary)
                                    Spacer()
                                    Text(slots.choices[index]?.title ?? localized("尚未選擇"))
                                        .foregroundStyle(DSColor.textSecondary)
                                        .multilineTextAlignment(.trailing)
                                    Image(systemName: "chevron.right")
                                        .font(DSFont.footnote)
                                        .foregroundStyle(DSColor.textTertiary)
                                        .accessibilityHidden(true)
                                }
                            }
                            .accessibilityIdentifier("discovery.category.configure.\(index)")
                        }
                    }
                    .interfaceSectionSurface()
                }
                .themedAppSurface(for: .explore)
                .navigationTitle(localized("設定五個分類"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(localized("關閉"), action: close)
                    }
                }
                .navigationDestination(item: $opened) { index in
                    let current = slots.choices[index]
                    List {
                        Section {
                            ForEach(catalog) { choice in
                                Button { choose(choice, index) } label: {
                                    HStack {
                                        Text(choice.title)
                                        Spacer()
                                        if choice.id == current?.id {
                                            Image(systemName: "checkmark").accessibilityHidden(true)
                                        }
                                    }
                                }
                                .accessibilityAddTraits(choice.id == current?.id ? [.isSelected] : [])
                            }
                        }
                        .interfaceSectionSurface()
                    }
                    .navigationTitle(localized("分類"))
                    .navigationBarTitleDisplayMode(.inline)
                    .themedAppSurface(for: .explore)
                    // Use the system chevron (including swipe-back), without the parent title.
                    .toolbarRole(.editor)
                }
                .task { if let openSlot, opened == nil { opened = openSlot } }
            }
        }
    }
}


/// Pick the owner of the entire Search feed, before selecting any of its categories.
struct DiscoverySearchSourcePicker: View {
    let sources: [BookSource]
    let selectedURL: String?
    let choose: (BookSource) -> Void
    let close: () -> Void
    @State private var query = ""

    private var results: [BookSource] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return sources.filter {
            term.isEmpty || $0.bookSourceName.localizedStandardContains(term)
                || $0.bookSourceUrl.localizedStandardContains(term)
        }
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
