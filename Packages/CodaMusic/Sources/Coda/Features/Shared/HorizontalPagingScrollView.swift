import SwiftUI

/// Remote paging is optional: fixed server batches still reveal their contents
/// in windows, without requesting the same recommendation batch repeatedly.
struct HorizontalPageLoading {
    var hasMore = false
    var isLoading = false
    var error: String?
    var loadMore: (() async -> Void)?
    var revision = 0
}

struct HorizontalPageWindow: Equatable {
    private(set) var limit: Int
    let pageSize: Int

    init(pageSize: Int) {
        self.pageSize = max(1, pageSize)
        limit = max(1, pageSize)
    }

    func visibleCount(total: Int) -> Int { min(max(0, total), limit) }

    mutating func advance(total: Int) {
        guard limit < total else { return }
        limit = min(total, limit + pageSize)
    }
}

/// One scroll owner for all data shelves. The boundary is measured in the
/// viewport, so eager card stacks cannot accidentally fetch every page at once.
struct HorizontalPagingScrollView<Content: View, Placeholder: View>: View {
    let itemCount: Int
    let resetKey: AnyHashable
    var horizontalInset: CGFloat = Theme.Layout.contentInset
    var spacing: CGFloat = Theme.Spacing.component
    var loading = HorizontalPageLoading()
    @ViewBuilder var content: (Int) -> Content
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var window: HorizontalPageWindow
    @State private var viewport = CGRect.zero
    @State private var nearEnd = false
    @State private var coordinateSpace = UUID()

    init(itemCount: Int, resetKey: AnyHashable, pageSize: Int = 12,
         horizontalInset: CGFloat = Theme.Layout.contentInset,
         spacing: CGFloat = Theme.Spacing.component,
         loading: HorizontalPageLoading = .init(),
         @ViewBuilder content: @escaping (Int) -> Content,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.itemCount = itemCount
        self.resetKey = resetKey
        self.horizontalInset = horizontalInset
        self.spacing = spacing
        self.loading = loading
        self.content = content
        self.placeholder = placeholder
        _window = State(initialValue: HorizontalPageWindow(pageSize: pageSize))
    }

    private struct RequestKey: Equatable {
        let reset: AnyHashable
        let count: Int
        let limit: Int
        let nearEnd: Bool
        let hasMore: Bool
        let error: String?
        let revision: Int
    }

    var body: some View {
        ScenePreservingScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                content(window.visibleCount(total: itemCount))
                Color.clear
                    .frame(width: 1, height: 1)
                    .onGeometryChange(for: Bool.self) { geometry in
                        let frame = geometry.frame(in: .named(coordinateSpace))
                        return viewport.width > 0 && frame.minX <= viewport.maxX + 80
                            && frame.maxX >= viewport.minX
                    } action: { nearEnd = $0 }
                if loading.isLoading {
                    placeholder()
                        .padding(.leading, spacing)
                        .allowsHitTesting(false)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("正在加载更多")
                } else if loading.error != nil {
                    Button("加载更多失败，点击重试") {
                        Task { await loading.loadMore?() }
                    }
                    .padding(.leading, spacing)
                }
            }
            .padding(.horizontal, horizontalInset)
        }
        .coordinateSpace(name: coordinateSpace)
        .onGeometryChange(for: CGRect.self) { geometry in
            CGRect(origin: .zero, size: geometry.size)
        } action: { viewport = $0 }
        .onChange(of: resetKey) { _ in
            window = HorizontalPageWindow(pageSize: window.pageSize)
        }
        .task(id: RequestKey(reset: resetKey, count: itemCount, limit: window.limit,
                             nearEnd: nearEnd, hasMore: loading.hasMore, error: loading.error, revision: loading.revision)) {
            guard nearEnd else { return }
            if window.visibleCount(total: itemCount) < itemCount {
                window.advance(total: itemCount)
            } else if loading.hasMore, !loading.isLoading, loading.error == nil {
                await loading.loadMore?()
            }
        }
    }
}

struct HorizontalCardLoadingColumn: View {
    var rows = 1
    var width: CGFloat = Theme.Layout.cardSize
    var circular = false
    var cornerRadius: CGFloat = Theme.Radius.cover

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.group) {
            ForEach(0..<rows, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                    SkeletonView(cornerRadius: circular ? 1000 : cornerRadius)
                        .frame(width: width, height: width)
                    SkeletonView(cornerRadius: 4).frame(width: width * 0.8, height: 16)
                    SkeletonView(cornerRadius: 4).frame(width: width * 0.6, height: 12)
                }
            }
        }
        .frame(width: width)
    }
}

struct HorizontalRemotePage<Item> {
    let items: [Item]
    let hasMore: Bool
}

/// Offset, duplicate protection, retries and request invalidation are shared by
/// paginated album shelves, rather than reimplemented in each destination.
@MainActor
final class HorizontalPageSource<Item: Identifiable>: ObservableObject {
    @Published private(set) var items: [Item] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasMore = false
    @Published private(set) var error: String?
    private(set) var offset = 0
    let pageSize: Int
    private var generation = UUID()

    init(pageSize: Int) { self.pageSize = max(1, pageSize) }

    func invalidate() {
        generation = UUID()
        isLoading = false
        error = nil
    }

    func replace(_ items: [Item], hasMore: Bool) {
        generation = UUID()
        var seen = Set<Item.ID>()
        self.items = items.filter { seen.insert($0.id).inserted }
        offset = items.count
        self.hasMore = hasMore
        isLoading = false
        error = nil
    }

    func loading(using loader: @escaping (Int, Int) async throws -> HorizontalRemotePage<Item>) -> HorizontalPageLoading {
        .init(hasMore: hasMore, isLoading: isLoading, error: error,
              loadMore: { [weak self] in await self?.loadMore(using: loader) }, revision: offset)
    }

    func loadMore(using loader: (Int, Int) async throws -> HorizontalRemotePage<Item>) async {
        guard hasMore, !isLoading else { return }
        let request = generation
        let authentication = MusicProviderContext.shared.authenticationKey
        isLoading = true
        error = nil
        defer { if generation == request { isLoading = false } }
        do {
            let page = try await loader(pageSize, offset)
            guard !Task.isCancelled, request == generation,
                  authentication == MusicProviderContext.shared.authenticationKey else { return }
            var seen = Set(items.map(\.id))
            let additions = page.items.filter { seen.insert($0.id).inserted }
            items += additions
            offset += page.items.count
            hasMore = page.hasMore && !additions.isEmpty
        } catch {
            guard !Task.isCancelled, request == generation,
                  authentication == MusicProviderContext.shared.authenticationKey else { return }
            self.error = error.localizedDescription
        }
    }
}
