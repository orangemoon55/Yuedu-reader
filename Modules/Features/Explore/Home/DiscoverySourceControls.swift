import Combine
import SwiftUI

/// The selected source owns its menus and scripts; no app-defined gender/mode controls.
struct DiscoverySourceControls: View {
    let source: BookSource
    let filterValues: [String: String]
    let onSearch: () -> Void
    let onSwitchSource: () -> Void
    let onReload: ([String: String], [DiscoverCardItem], String?) -> Void
    @StateObject private var discover: DiscoverViewModel
    @StateObject private var browser = BrowserState()
    @State private var showsSettings = false
    @State private var showsLogin = false
    @State private var pendingAddress: String?
    @State private var browserAddress: BrowserAddress?
    @State private var restoredFilters = false

    private struct BrowserAddress: Identifiable { let id = UUID(); let address: String }

    init(source: BookSource, filterValues: [String: String], onSearch: @escaping () -> Void,
         onSwitchSource: @escaping () -> Void,
         onReload: @escaping ([String: String], [DiscoverCardItem], String?) -> Void) {
        self.source = source
        self.filterValues = filterValues
        self.onSearch = onSearch
        self.onSwitchSource = onSwitchSource
        self.onReload = onReload
        _discover = StateObject(wrappedValue: DiscoverViewModel(source: source))
    }

    private var currentSource: BookSource { discover.selectedSource ?? source }
    private var sourceTitle: String { BookSourceDisplayName.title(currentSource.bookSourceName) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DSSpacing.sm) {
                Menu {
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
                Text(sourceTitle.isEmpty ? localized("未命名來源配置") : sourceTitle)
                    .font(DSFont.caption)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onSearch) { controlLabel("搜索") }
                    .accessibilityLabel(localized("源內搜索"))
                Button(action: onSwitchSource) { controlLabel("切換") }
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

    private func controlLabel(_ title: String) -> some View {
        Text(localized(title))
            .font(DSFont.body.weight(.medium))
            .padding(.horizontal, DSSpacing.md)
            .frame(minWidth: DSLayout.minimumTapTarget, minHeight: DSLayout.minimumTapTarget)
            .background { NavigationGlassCapsule(tint: DSColor.accent) }
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
        onReload(values, discover.items, discover.exploreError)
    }

    private func reloadAfterSourceChange(_ notification: Notification) {
        guard notification.userInfo?["sourceURL"] as? String == source.bookSourceUrl else { return }
        restoredFilters = true
        discover.reload(forceRefresh: true)
    }

    private func openPendingPage() {
        guard let address = pendingAddress else { return }
        pendingAddress = nil
        browserAddress = .init(address: address)
    }
}
