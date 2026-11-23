import Combine
import SwiftUI

/// The selected source owns its menus and scripts; no app-defined gender/mode controls.
struct DiscoverySourceControls<Catalog: View>: View {
    let source: BookSource
    let catalog: Catalog
    let onSwitchSource: () -> Void
    let onReload: ([String: String], [DiscoverCardItem], String?, Bool) -> Void
    @ScaledMetric(relativeTo: .caption) private var sourceTitleSize: CGFloat = 14
    @StateObject private var discover: DiscoverViewModel
    @StateObject private var browser = BrowserState()
    @State private var showsSettings = false
    @State private var showsLogin = false
    @State private var pendingAddress: String?
    @State private var browserAddress: BrowserAddress?
    @State private var pendingBookRefresh = false

    private struct BrowserAddress: Identifiable { let id = UUID(); let address: String }

    init(source: BookSource, onSwitchSource: @escaping () -> Void,
         onReload: @escaping ([String: String], [DiscoverCardItem], String?, Bool) -> Void,
         @ViewBuilder catalog: () -> Catalog) {
        self.source = source
        self.onSwitchSource = onSwitchSource
        self.onReload = onReload
        self.catalog = catalog()
        _discover = StateObject(wrappedValue: DiscoverViewModel(source: source))
    }

    private var currentSource: BookSource { discover.selectedSource ?? source }
    private var sourceTitle: String { BookSourceDisplayName.title(currentSource.bookSourceName) }

    var body: some View {
        VStack(spacing: DSSpacing.xxs) {
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
                        .font(.system(size: 16, weight: .medium))
                        // Match the switch button's visible circle, not its larger hit area.
                        .frame(width: 32, height: 32)
                        .background { NavigationGlassCapsule(tint: DSColor.accent) }
                }
                // Native Menu may add its own circle outside the 32pt label on new iOS.
                // Bound its drawing before expanding only the invisible hit target.
                .buttonStyle(.plain)
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .frame(width: DSLayout.minimumTapTarget, height: DSLayout.minimumTapTarget)
                .contentShape(Rectangle())
                .accessibilityLabel(localized("更多"))
                .accessibilityIdentifier("discovery.source.more")
                Text(sourceTitle.isEmpty ? localized("未命名來源配置") : sourceTitle)
                    .font(GlobalAppTypography.fixedFont(size: sourceTitleSize))
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
            .frame(minHeight: DSLayout.minimumTapTarget)
            .padding(.horizontal, DSSpacing.lg)
            .buttonStyle(.plain)
            catalog
            if !discover.filters.isEmpty || !discover.pageItems.isEmpty {
                DiscoverControlsRow(discover: discover, pageItems: discover.pageItems) {
                    browserAddress = .init(address: $0)
                }
            }
            if discover.isLoadingItems {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, DSSpacing.xs)
            }
        }
        // Keep the source buttons and the height-bounded filters in separate rows,
        // even when the book list or a keyboard compresses the available height.
        .fixedSize(horizontal: false, vertical: true)
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
        .onChange(of: discover.shownCategoryKeys) { _, _ in
            // A selection edit changes no loading flag. Publish it to the Search catalogue
            // immediately instead of waiting for a later unrelated network reload.
            if !discover.isLoadingItems { didReload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookSourceLoginInfoDidChange)
            .receive(on: DispatchQueue.main)) { notification in reloadAfterSourceChange(notification) }
        .onReceive(NotificationCenter.default.publisher(for: .bookSourceUserVariableDidChange)
            .receive(on: DispatchQueue.main)) { notification in reloadAfterSourceChange(notification) }
    }

    private func didReload() {
        let values = Dictionary(discover.filters.map { ($0.paramKey, $0.selected) },
                                uniquingKeysWith: { first, _ in first })
        let refreshBooks = pendingBookRefresh
        pendingBookRefresh = false
        let visible = discover.items.filter { !$0.isFetchable || discover.isCategoryShown($0) }
        // Preserve the source's explanatory labels/API failure when there are no
        // navigable categories; otherwise the source page loses its only diagnosis.
        let notice = visible.contains(where: \.isFetchable) ? nil : discover.sourceNotice
        onReload(values, visible, discover.exploreError ?? notice, refreshBooks)
    }

    private func reloadAfterSourceChange(_ notification: Notification) {
        guard notification.userInfo?["sourceURL"] as? String == source.bookSourceUrl else { return }
        pendingBookRefresh = true
        discover.reload(forceRefresh: true)
    }

    private func openPendingPage() {
        guard let address = pendingAddress else { return }
        pendingAddress = nil
        browserAddress = .init(address: address)
    }
}
