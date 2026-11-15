import SwiftUI

struct BookDetailSourceAuthorWorksSection: View {
    let state: SourceAuthorWorks.State
    let source: BookSource
    let onSelect: (OnlineBook) -> Void
    let onRetry: () -> Void

    private var isVisible: Bool {
        switch state {
        case .loaded(let books): !books.isEmpty
        case .failed: true
        case .hidden, .loading: false
        }
    }

    var body: some View {
        if isVisible {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                BookDetailSectionHeader(title: localized("作者其他作品"), actionTitle: nil, action: nil)
                    .padding(.horizontal, DSSpacing.lg)
                switch state {
                case .loaded(let books):
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: DSSpacing.md) {
                            ForEach(books) { display in
                                Button { onSelect(display.book) } label: {
                                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                                        BookCoverImage(
                                            coverURL: display.book.coverUrl,
                                            title: display.book.name,
                                            author: display.book.author,
                                            sourceBaseURL: source.bookSourceUrl,
                                            sourceHeaders: source.parsedHeaders
                                        )
                                        .frame(width: DSLayout.discoverShelfCoverWidth,
                                               height: DSLayout.discoverShelfCoverHeight)
                                        .clipShape(RoundedRectangle(cornerRadius: DSRadius.sm, style: .continuous))
                                        Text(display.book.name)
                                            .font(DSFont.footnote.weight(.medium))
                                            .foregroundStyle(DSColor.textPrimary)
                                            .lineLimit(2, reservesSpace: true)
                                        Text(display.book.author)
                                            .font(DSFont.caption)
                                            .foregroundStyle(DSColor.textSecondary)
                                            .lineLimit(1, reservesSpace: true)
                                    }
                                    .frame(width: DSLayout.discoverShelfCoverWidth, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("detail.sourceAuthorWorks.book")
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.hidden)
                    .contentMargins(.horizontal, DSSpacing.lg, for: .scrollContent)
                    .scrollTargetBehavior(.viewAligned)
                    .scrollClipDisabled()
                case .failed:
                    Button(action: onRetry) {
                        Label(localized("載入失敗，點按重試"), systemImage: "arrow.clockwise")
                            .font(DSFont.subheadline)
                            .foregroundStyle(DSColor.accent)
                            .frame(maxWidth: .infinity, minHeight: DSLayout.discoverShelfCoverHeight)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, DSSpacing.lg)
                case .hidden, .loading:
                    EmptyView()
                }
            }
        }
    }
}
