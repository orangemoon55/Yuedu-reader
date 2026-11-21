import SwiftUI

/// The source configuration sheet. Scrolling changes no source order or reader position.
struct DiscoverySourcePickerList: View {
    let sources: [BookSource]
    let selectedURL: String?
    let choose: (BookSource) -> Void
    let close: () -> Void
    @ObservedObject private var store: BookSourceStore
    @State private var pins: DiscoverySourcePins
    @State private var query = ""
    @State private var viewport = CGRect.zero
    @State private var edgeFrames: [ReaderTOCEdge: CGRect] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(sources: [BookSource], selectedURL: String?,
         choose: @escaping (BookSource) -> Void, close: @escaping () -> Void,
         store: BookSourceStore = .shared, pins: DiscoverySourcePins? = nil) {
        self.sources = sources
        self.selectedURL = selectedURL
        self.choose = choose
        self.close = close
        _store = ObservedObject(wrappedValue: store)
        _pins = State(initialValue: pins ?? DiscoverySourcePins())
    }

    @State private var displayedSources: [BookSource] = []
    @State private var didLocateSelection = false

    private func rebuildRows(from snapshot: [BookSource]) {
        // Publisher payloads are current even during @Published's willSet callback.
        // Filtering runs on data/query/pin changes, never for a scroll-frame preference.
        let allowed = Set(sources.map(\.id))
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        displayedSources = pins.orderedBookSources(snapshot.filter {
            allowed.contains($0.id) && (term.isEmpty
                || $0.bookSourceName.localizedStandardContains(term)
                || $0.bookSourceUrl.localizedStandardContains(term))
        })
    }

    private var initialLocationTarget: UUID? {
        guard !didLocateSelection else { return nil }
        return SourcePickerActions.initialSelectionID(in: displayedSources, selectedURL: selectedURL)
    }

    private var isAtLatest: Bool {
        ReaderTOCEdgeVisibility.isAtLatest(row: edgeFrames[.latest], viewport: viewport,
                                          verticalColumns: false)
    }

    var body: some View {
        let rows = displayedSources
        ScrollViewReader { proxy in
            List {
                Section {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, source in
                        row(source)
                            .id(source.id)
                            .reportTOCEdges(index: index, first: rows.isEmpty ? nil : 0,
                                           latest: rows.isEmpty ? nil : rows.count - 1)
                    }
                }
                .interfaceSectionSurface()
            }
            .listStyle(.plain)
            .listSectionSpacing(0)
            .contentMargins(.top, 0, for: .scrollContent)
            .environment(\.defaultMinListRowHeight, 44)
            .onAppear { rebuildRows(from: store.sources) }
            .onReceive(store.sourcesPublisher) { rebuildRows(from: $0) }
            .onChange(of: sources.map(\.id)) { _, _ in rebuildRows(from: store.sources) }
            .onChange(of: query) { _, _ in rebuildRows(from: store.sources) }
            .onChange(of: pins.pinnedIDs) { _, _ in rebuildRows(from: store.sources) }
            .task(id: initialLocationTarget) {
                guard let target = initialLocationTarget else { return }
                await Task.yield()
                guard !Task.isCancelled, !didLocateSelection else { return }
                proxy.scrollTo(target, anchor: .center)
                didLocateSelection = true
            }
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: SourcePickerViewportKey.self,
                                           value: geometry.frame(in: .global))
                }
            }
            .onPreferenceChange(SourcePickerViewportKey.self) { viewport = $0 }
            .onPreferenceChange(ReaderTOCEdgeFramesKey.self) { edgeFrames = $0 }
            .onChange(of: rows.map(\.id)) { _, _ in edgeFrames = [:] }
            .navigationTitle(localized("來源配置"))
            .navigationBarTitleDisplayMode(.inline)
            .themedAppSurface(for: .explore)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: localized("搜尋來源配置名稱或網址"))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if rows.isEmpty {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView(localized("沒有來源配置"), systemImage: "books.vertical")
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("關閉"), action: close)
                        .accessibilityIdentifier("discovery.source.close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let toTop = isAtLatest
                        guard let target = SourcePickerActions.edgeID(in: rows, toTop: toTop) else { return }
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
                            proxy.scrollTo(target, anchor: toTop ? .top : .bottom)
                        }
                    } label: {
                        Text(localized(isAtLatest ? "回頂部" : "去底部"))
                    }
                    .disabled(rows.isEmpty)
                    .accessibilityIdentifier("discovery.source.edge")
                }
            }
        }
    }

    private func row(_ source: BookSource) -> some View {
        let selected = source.bookSourceUrl == selectedURL
        return Button { choose(source) } label: {
            HStack {
                if pins.isPinned(source.id) {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(DSColor.accent)
                        .accessibilityHidden(true)
                }
                Text(BookSourceDisplayName.title(source.bookSourceName))
                    .lineLimit(2)
                Spacer()
                if selected { Image(systemName: "checkmark").accessibilityHidden(true) }
            }
            .foregroundStyle(DSColor.textPrimary)
            .contentShape(Rectangle())
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("discovery.source.choose.\(source.bookSourceUrl)")
        .accessibilityValue(pins.isPinned(source.id) ? localized("已置頂") : "")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { delete(source) } label: {
                Label(localized("刪除"), systemImage: "trash")
            }
            .accessibilityIdentifier("discovery.source.delete.\(source.id)")
            Button {
                pins.togglePin(source.id, availableIDs: Set(store.sources.map(\.id)))
            } label: {
                Label(localized(pins.isPinned(source.id) ? "取消置頂" : "置頂"),
                      systemImage: pins.isPinned(source.id) ? "pin.slash" : "pin")
            }
            .tint(DSColor.accent)
        }
        .accessibilityAction(named: Text(localized("刪除"))) { delete(source) }
    }

    private func delete(_ source: BookSource) {
        _ = SourcePickerActions.delete(sourceID: source.id, store: store, pins: pins)
        edgeFrames = [:]
    }
}

private struct SourcePickerViewportKey: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

@MainActor
enum SourcePickerActions {
    static func initialSelectionID(in sources: [BookSource], selectedURL: String?) -> UUID? {
        guard let selectedURL else { return nil }
        return sources.first { $0.bookSourceUrl == selectedURL }?.id
    }

    static func edgeID(in sources: [BookSource], toTop: Bool) -> UUID? {
        toTop ? sources.first?.id : sources.last?.id
    }

    /// Delete the persisted source, not a filtered/display-only copy. The store's
    /// mutation revision protects this deletion from stale cloud-sync snapshots.
    @discardableResult
    static func delete(sourceID: UUID, store: BookSourceStore, pins: DiscoverySourcePins,
                       defaults: UserDefaults = .standard) -> Bool {
        guard let removed = store.source(id: sourceID), store.delete(id: sourceID) > 0 else { return false }
        pins.removePin(sourceID)
        // Other configurations with the same URL remain valid if one still exists.
        if !store.sources.contains(where: { $0.bookSourceUrl == removed.bookSourceUrl }) {
            let remembered = "yd_discovery_five_categories.v1.source."
            for (key, value) in defaults.dictionaryRepresentation()
                where key.hasPrefix(remembered) || key == SourceDiscoverySelection.preferenceKey {
                if value as? String == removed.bookSourceUrl { defaults.removeObject(forKey: key) }
            }
        }
        return true
    }
}
