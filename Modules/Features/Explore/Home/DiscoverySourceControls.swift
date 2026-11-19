import Combine
import SwiftUI

/// The selected source owns its menus and scripts; no app-defined gender/mode controls.
struct DiscoverySourceControls: View {
    let source: BookSource
    let filterValues: [String: String]
    let onSearch: () -> Void
    let onSwitchSource: () -> Void
    let onAllTypes: (() -> Void)?
    let onReload: ([String: String], [DiscoverCardItem], String?, Bool) -> Void
    @StateObject private var discover: DiscoverViewModel
    @StateObject private var browser = BrowserState()
    @State private var showsSettings = false
    @State private var showsLogin = false
    @State private var pendingAddress: String?
    @State private var browserAddress: BrowserAddress?
    @State private var restoredFilters = false
    @State private var pendingBookRefresh = false

    private struct BrowserAddress: Identifiable { let id = UUID(); let address: String }

    init(source: BookSource, filterValues: [String: String], onSearch: @escaping () -> Void,
         onSwitchSource: @escaping () -> Void, onAllTypes: (() -> Void)? = nil,
         onReload: @escaping ([String: String], [DiscoverCardItem], String?, Bool) -> Void) {
        self.source = source
        self.filterValues = filterValues
        self.onSearch = onSearch
        self.onSwitchSource = onSwitchSource
        self.onAllTypes = onAllTypes
        self.onReload = onReload
        _discover = StateObject(wrappedValue: DiscoverViewModel(source: source))
    }

    private var currentSource: BookSource { discover.selectedSource ?? source }
    private var sourceTitle: String { BookSourceDisplayName.title(currentSource.bookSourceName) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DSSpacing.sm) {
                Menu {
                    if let onAllTypes {
                        Button(action: onAllTypes) {
                            Label(localized("所有類型"), systemImage: "square.grid.2x2")
                        }
                        .accessibilityIdentifier("search.allTypes")
                    }
                    Button(action: onSearch) {
                        Label(localized("源內搜索"), systemImage: "magnifyingglass")
                    }
                    Button { showsSettings = true } label: {
                        Label(localized("發現頁設定"), systemImage: "gearshape")
                    }
                    if !currentSource.loginUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button { showsLogin = true } label: {
                            Label(localized("登入"), systemImage: "person.crop.circle")
                        }
                    }
                } label: {
                    Label(localized("更多"), systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 20))
                        .frame(width: DSLayout.minimumTapTarget, height: DSLayout.minimumTapTarget)
                        .background { NavigationGlassCapsule(tint: DSColor.accent) }
                }
                .accessibilityLabel(localized("更多"))
                .accessibilityIdentifier("discovery.source.more")
                Text(sourceTitle.isEmpty ? localized("未命名來源配置") : sourceTitle)
                    .font(DSFont.caption)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onSwitchSource) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(DSColor.textPrimary)
                        .frame(width: 32, height: 32)
                        .background { NavigationGlassCapsule(tint: DSColor.accent) }
                        .frame(width: DSLayout.minimumTapTarget, height: DSLayout.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                    .accessibilityLabel(localized("切換來源配置"))
                    .accessibilityIdentifier("discovery.category.change")
            }
            .padding(.horizontal, DSSpacing.lg)
            .buttonStyle(.plain)
            if !discover.filters.isEmpty || !discover.pageItems.isEmpty {
                DiscoverControlsRow(discover: discover, pageItems: discover.pageItems) {
                    browserAddress = .init(address: $0)
                }
            }
            if discover.isLoadingItems {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, DSSpacing.xs)
            }
        }
        .sheet(isPresented: $showsSettings, onDismiss: openPendingPage) {
            DiscoverPageSettingsSheet(discover: discover) { pendingAddress = $0 }
        }
        .sheet(isPresented: $showsLogin) {
            BookSourceLoginSheet(source: currentSource) { showsLogin = false }
        }
        .fullScreenCover(item: $browserAddress) { address in
            NavigationStack { BrowserPage(browser: browser, entry: .open(address.address)) }
        }
        .onAppear { discover.refreshSources() }
        .onChange(of: discover.isLoadingItems) { _, loading in
            if !loading { didReload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookSourceLoginInfoDidChange)
            .receive(on: DispatchQueue.main)) { notification in reloadAfterSourceChange(notification) }
        .onReceive(NotificationCenter.default.publisher(for: .bookSourceUserVariableDidChange)
            .receive(on: DispatchQueue.main)) { notification in reloadAfterSourceChange(notification) }
    }

    private func didReload() {
        // Restore a persisted section's filters through the original JS/infoMap path.
        // Once restored, subsequent user/script changes are authoritative.
        if !restoredFilters, discover.exploreError == nil,
           let filter = discover.filters.first(where: {
               guard let value = filterValues[$0.paramKey] else { return false }
               return value != $0.selected && $0.options.contains(value)
           }), let value = filterValues[filter.paramKey] {
            discover.selectFilter(filter, value: value)
            return
        }
        restoredFilters = true
        let values = Dictionary(discover.filters.map { ($0.paramKey, $0.selected) },
                                uniquingKeysWith: { first, _ in first })
        let refreshBooks = pendingBookRefresh
        pendingBookRefresh = false
        onReload(values, discover.items, discover.exploreError, refreshBooks)
    }

    private func reloadAfterSourceChange(_ notification: Notification) {
        guard notification.userInfo?["sourceURL"] as? String == source.bookSourceUrl else { return }
        restoredFilters = true
        pendingBookRefresh = true
        discover.reload(forceRefresh: true)
    }

    private func openPendingPage() {
        guard let address = pendingAddress else { return }
        pendingAddress = nil
        browserAddress = .init(address: address)
    }
}
