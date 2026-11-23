import SwiftUI

// Shared review UI from the upstream comments implementation, adapted to this
// branch's existing design tokens; no detail-page navigation is replaced.
struct WorkReviewCard: View {
    let review: WorkReview
    /// In 作品詳情's row: a few lines, and as tall as its neighbours.
    var isPreview = false
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            if let title = review.title {
                Text(verbatim: title)
                    .font(DSFont.subheadline.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(isPreview ? 1 : 2)
            }
            Text(verbatim: review.text)
                .font(DSFont.subheadline)
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(isPreview ? 4 : nil)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: isPreview ? .infinity : nil, alignment: .topLeading)
            if review.rating != nil || !review.byline(locale: locale).isEmpty || review.likes != nil {
                HStack(spacing: DSSpacing.sm) {
                    if let rating = review.rating {
                        WorkRatingStars(rating: rating)
                    }
                    Text(verbatim: review.byline(locale: locale))
                        .lineLimit(1)
                    if let likes = review.likes {
                        Spacer(minLength: DSSpacing.sm)
                        HStack(spacing: DSSpacing.xs) {
                            Image(systemName: "hand.thumbsup")
                                .accessibilityHidden(true)
                            Text(likes, format: .number)
                                .monospacedDigit()
                        }
                    }
                }
                .font(DSFont.footnote)
                .foregroundStyle(DSColor.textSecondary)
            }
        }
        .padding(DSSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: isPreview ? .infinity : nil, alignment: .topLeading)
        .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous))
    }
}

/// A rating as five stars, to the nearest half. Drawn only: its number is spoken by whatever
/// holds it.
struct WorkRatingStars: View {
    let rating: Double

    var body: some View {
        HStack(spacing: 0) {
            ForEach(1...WorkRating.stars, id: \.self) { star in
                Image(systemName: Self.symbol(for: star, rating: rating))
            }
        }
        .accessibilityHidden(true)
    }

    /// Full from its own number up, half from half a star below it.
    static func symbol(for star: Int, rating: Double) -> String {
        let halves = (rating * 2).rounded()
        if halves >= Double(star * 2) { return "star.fill" }
        return halves >= Double(star * 2 - 1) ? "star.leadinghalf.filled" : "star"
    }
}

extension WorkReview {
    /// 「2025年1月2日 · 讀者名」, each part only when the review has it. The day is the one the
    /// site wrote: its date is read as UTC (`RuleModuleClient.date`), so it is shown in UTC too,
    /// never a day later for a reader east of it.
    func byline(locale: Locale) -> String {
        let day = date.map { $0.formatted(Date.FormatStyle(date: .long, time: .omitted, locale: locale, timeZone: .gmt)) }
        return [day, author].compactMap { $0 }.joined(separator: " · ")
    }

    /// The card as VoiceOver reads it: headline, text, rating, day and writer.
    func spokenText(locale: Locale) -> String {
        var parts = [title, text].compactMap { $0 }
        if let rating { parts.append(WorkRating.spoken(rating, locale: locale)) }
        let byline = byline(locale: locale)
        if !byline.isEmpty { parts.append(byline) }
        if let likes { parts.append(String(format: localized("%d 人覺得有幫助"), likes)) }
        return parts.joined(separator: "\n")
    }
}

extension WorkRating {
    /// 「3.3」: one decimal, in the reader's numerals.
    static func text(_ stars: Double, locale: Locale) -> String {
        stars.formatted(.number.precision(.fractionLength(1)).locale(locale))
    }

    /// 「3.3 顆星，滿分 5 顆星」.
    static func spoken(_ stars: Double, locale: Locale) -> String {
        String(format: localized("%@ 顆星，滿分 %d 顆星"), text(stars, locale: locale), Self.stars)
    }
}


extension View {
    /// A row of 讀者評論 and of 本章說: no separator, no row colour of its own over the page's background.
    func reviewRow() -> some View {
        listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: DSSpacing.sm, leading: DSSpacing.lg, bottom: DSSpacing.sm, trailing: DSSpacing.lg))
    }
}

/// The order 讀者評論 lists its reviews in.
enum WorkReviewOrder: Hashable, CaseIterable {
    /// As the site listed them.
    case site
    case newest
    case mostHelpful

    var title: String {
        switch self {
        case .site: localized("預設")
        case .newest: localized("最新")
        case .mostHelpful: localized("最有幫助")
        }
    }

    /// The site's order always; by day when a review has one, by helpfulness when one was marked.
    static func available(for reviews: [WorkReview]) -> [WorkReviewOrder] {
        var orders: [WorkReviewOrder] = [.site]
        if reviews.contains(where: { $0.date != nil }) { orders.append(.newest) }
        if reviews.contains(where: { $0.likes != nil }) { orders.append(.mostHelpful) }
        return orders
    }

    /// Stable: reviews the order cannot tell apart keep the site's order, and one without the
    /// value comes last.
    func sorted(_ reviews: [WorkReview]) -> [WorkReview] {
        switch self {
        case .site:
            return reviews
        case .newest:
            return reviews.enumerated().sorted { lhs, rhs in
                let left = lhs.element.date ?? .distantPast, right = rhs.element.date ?? .distantPast
                return left != right ? left > right : lhs.offset < rhs.offset
            }.map(\.element)
        case .mostHelpful:
            return reviews.enumerated().sorted { lhs, rhs in
                let left = lhs.element.likes ?? 0, right = rhs.element.likes ?? 0
                return left != right ? left > right : lhs.offset < rhs.offset
            }.map(\.element)
        }
    }
}

