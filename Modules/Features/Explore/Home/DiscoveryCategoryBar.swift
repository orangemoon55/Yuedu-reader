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
            ForEach(slots.choices.indices, id: \.self) { index in
                let choice = slots.choices[index]
                let selected = choice != nil && selection == index
                Button { select(index) } label: {
                    Text(choice?.title ?? String(format: localized("分類 %d"), index + 1))
                        .font((typeSize.isAccessibilitySize ? DSFont.caption : DSFont.subheadline).weight(.semibold))
                        .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                        .minimumScaleFactor(0.80)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(choice == nil ? DSColor.textSecondary : Color.primary)
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

/// Reuses the existing searchable source/category selector, including per-source filters.
struct DiscoverySlotSettings: View {
    let slots: DiscoveryCategorySlots
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
                    HomeSourceChoices(
                        current: current.map { .sourceCategories([$0.reference]) },
                        parameters: current.map { HomeSection.filterParameters($0.filters, sourceURL: $0.reference.sourceURL) } ?? [:],
                        choose: { value in
                            guard case .sourceCategories(let references) = value.binding,
                                  let ref = references.first else { return }
                            choose(.init(reference: ref, filters: value.filterValues), index)
                        }
                    )
                }
                .task { if let openSlot, opened == nil { opened = openSlot } }
            }
        }
    }
}
