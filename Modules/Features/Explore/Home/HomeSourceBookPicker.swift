import SwiftUI

struct HomeSourceBookPicker: View {
    let current: HomeSectionBinding?
    let isPushed: Bool
    let choose: (HomeSourceBook) -> Void
    let cancel: () -> Void
    @ObservedObject private var sources = BookSourceStore.shared
    @State private var filter = ""

    private var searchableSources: [BookSource] {
        sources.sources.filter {
            $0.enabled && !$0.searchUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (filter.isEmpty || $0.bookSourceName.localizedCaseInsensitiveContains(filter))
        }
    }

    var body: some View {
        List {
            if case .sourceBook(let book) = current {
                Section(localized("目前")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(book.title).foregroundStyle(DSColor.textPrimary)
                        Text(book.author).font(.subheadline).foregroundStyle(DSColor.textSecondary)
                    }
                }
            }
            Section {
                ForEach(searchableSources) { source in
                    NavigationLink {
                        HomeSourceBookSearch(source: source, choose: choose)
                    } label: {
                        Text(source.bookSourceName)
                    }
                    .accessibilityIdentifier("homeBookPicker.source.\(source.id)")
                }
            } header: {
                Text(localized("選擇書源"))
            } footer: {
                Text(localized("先選書源，再搜尋並選中一本書。首頁固定顯示你選定的書籍。"))
            }
            if searchableSources.isEmpty {
                Text(localized("沒有可搜尋的書源"))
                    .foregroundStyle(DSColor.textSecondary)
            }
        }
        .searchable(text: $filter, prompt: localized("篩選書源"))
        .navigationTitle(localized("指定書籍"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .explore)
        .toolbar {
            if !isPushed {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("取消"), action: cancel)
                }
            }
        }
    }
}

private struct HomeSourceBookSearch: View {
    let source: BookSource
    let choose: (HomeSourceBook) -> Void
    @StateObject private var model = HomeSourceBookPickerModel()
    @State private var query = ""
    @State private var submittedQuery = ""
    @State private var selectionTask: Task<Void, Never>?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        List {
            Section {
                ForEach(model.books) { book in
                    Button {
                        selectionTask = Task {
                            if let selection = await model.select(book, in: source) { choose(selection) }
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(book.name).font(.headline).foregroundStyle(DSColor.textPrimary)
                                if !book.author.isEmpty {
                                    Text(book.author).font(.subheadline).foregroundStyle(DSColor.textSecondary)
                                }
                                Text(String(book.bookUrl.prefix(180)))
                                    .font(.caption).foregroundStyle(DSColor.textTertiary).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            if model.selectingID == book.id { ProgressView() }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .disabled(model.selectingID != nil)
                    .accessibilityIdentifier("homeBookPicker.book.\(book.id)")
                }
            } header: {
                Text(source.bookSourceName)
            }
            if model.isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else if let error = model.error {
                Text(error).foregroundStyle(DSColor.textSecondary)
            } else if !submittedQuery.isEmpty, model.books.isEmpty {
                Text(localized("沒有找到書籍"))
            }
            if model.hasMore, !model.isLoading {
                Button(localized("載入更多")) {
                    searchTask = Task { await model.search(submittedQuery, in: source, more: true) }
                }
                .disabled(model.selectingID != nil)
            }
        }
        .searchable(text: $query, prompt: localized("搜尋書名或作者"))
        .onSubmit(of: .search) {
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, model.selectingID == nil else { return }
            submittedQuery = text
            searchTask?.cancel()
            searchTask = Task { await model.search(text, in: source) }
        }
        .navigationTitle(localized("選擇書籍"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .explore)
        .onDisappear {
            searchTask?.cancel()
            selectionTask?.cancel()
        }
    }
}

#Preview {
    NavigationStack {
        HomeSourceBookPicker(current: nil, isPushed: false, choose: { _ in }, cancel: {})
    }
}
