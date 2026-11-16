import SwiftUI

/// Fixed text slots keep the circular shelf anchored while the selected book changes.
/// Only Dynamic Type changes these dimensions; title length never does.
struct BookshelfRingReadingPrompt: View {
    let book: ReadingBook
    let context: BookshelfRingChapterContext
    var recommendation: String? = nil
    let onOpen: () -> Void
    @ScaledMetric(relativeTo: .headline) private var messageHeight: CGFloat = 46
    @ScaledMetric(relativeTo: .subheadline) private var chapterHeight: CGFloat = 22
    @ScaledMetric(relativeTo: .headline) private var resultHeight: CGFloat = 46

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                Text(recommendation ?? BookshelfRingChapterContext.dailyMessage(for: book.title))
                    .font(.headline)
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(2, reservesSpace: true)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(height: recommendation == nil ? messageHeight : resultHeight, alignment: .topLeading)
                Text(context.readingPrompt)
                    .font(.subheadline)
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: chapterHeight, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("bookshelf.ring.prompt")
    }
}

/// The cover occupies the full height of the card, sharing its outer clipping mask.
/// The text column has a fixed budget, so short and long titles have the same frame.
struct BookshelfRingSelectedCard: View {
    let book: ReadingBook
    let context: BookshelfRingChapterContext
    let colorScheme: ColorScheme
    let onOpen: () -> Void
    @ScaledMetric(relativeTo: .subheadline) private var cardHeight: CGFloat = 156
    @ScaledMetric(relativeTo: .subheadline) private var titleHeight: CGFloat = 36

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 0) {
                ShelfCoverSlot(book: book, colorScheme: colorScheme,
                               displaySize: BookshelfRingPresentation.coverDecodeSize)
                    .frame(width: min(120, cardHeight * 0.68), height: cardHeight)
                    .clipped()
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("bookshelf.ring.selected.cover")
                VStack(alignment: .leading, spacing: 5) {
                    Text(book.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(2, reservesSpace: true)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .frame(height: titleHeight, alignment: .topLeading)
                    Text(book.author.isEmpty ? localized("未知作者") : book.author)
                        .font(.caption)
                        .foregroundStyle(DSColor.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(context.currentChapterLine)
                        .font(.caption)
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(1)
                    Text(context.latestChapterLine)
                        .font(.caption2)
                        .foregroundStyle(DSColor.textSecondary)
                        .lineLimit(1)
                    HStack(alignment: .firstTextBaseline) {
                        Text(localized("閱讀進度"))
                            .font(.caption2)
                            .foregroundStyle(DSColor.textSecondary)
                        Spacer(minLength: 4)
                        Text(BookshelfRingGeometry.progress(book.currentPosition), format: .percent.precision(.fractionLength(0)))
                            .font(.subheadline.weight(.medium).monospacedDigit())
                            .foregroundStyle(DSColor.textPrimary)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(DSColor.accent)
                            .accessibilityHidden(true)
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(height: cardHeight)
            .background(DSColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16).stroke(DSColor.border.opacity(0.5), lineWidth: 0.8)
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("bookshelf.ring.selected")
    }
}
