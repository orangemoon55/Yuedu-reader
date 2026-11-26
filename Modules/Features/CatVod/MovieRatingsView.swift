import SwiftUI

/// Shared by the home hero and detail page. Source scores render immediately; optional
/// TMDB lookup is independently cancellable and cannot delay browsing or episode playback.
struct MovieRatingsView: View {
    let video: CatVodVideo
    var compact = false
    var centered = false
    @AppStorage(TMDBSettings.enabledKey) private var tmdbEnabled = false
    @AppStorage(TMDBSettings.revisionKey) private var credentialRevision = 0
    @State private var enriched: MovieRating?
    @State private var failure: String?
    @State private var retry = 0
    @State private var completedRequest: Request?

    private struct Request: Hashable {
        let video: CatVodVideo
        let enabled: Bool
        let revision: Int
        let retry: Int
    }
    private var request: Request {
        Request(video: video, enabled: tmdbEnabled, revision: credentialRevision, retry: retry)
    }
    private var ratings: [MovieRating] {
        MovieRatingParser.merging(video.ratings, tmdb: tmdbEnabled && completedRequest == request ? enriched : nil)
    }

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: DSSpacing.xs) {
            if !ratings.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.md) {
                        ForEach(ratings, id: \.provider) { rating in badge(rating) }
                    }
                    .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                }
                .accessibilityIdentifier("movie.ratings")
            }
            if !compact, completedRequest == request, let failure {
                HStack {
                    Text(failure).font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                    Button(localized("重试")) { retry += 1 }.font(DSFont.caption)
                }
                .accessibilityIdentifier("movie.ratings.retry")
            }
            if ratings.contains(where: { $0.origin == .tmdbAPI }) {
                Text(localized("TMDB 数据；本产品未经 TMDB 认可或认证。"))
                    .font(DSFont.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(centered ? .center : .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .task(id: request) {
            let started = request
            enriched = nil; failure = nil; completedRequest = nil
            guard tmdbEnabled else { return }
            do {
                let result = try await TMDBClient.shared.rating(for: video)
                try Task.checkCancellation()
                guard started == request else { return }
                enriched = result; completedRequest = started
            } catch {
                guard !Task.isCancelled, started == request else { return }
                // Never print URLs, source credentials or errors carrying an API-key query.
                failure = localized("TMDB 评分暂时无法加载，片源与播放不受影响。")
                completedRequest = started
            }
        }
    }

    private func badge(_ rating: MovieRating) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: 2) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "star.fill").foregroundStyle(.orange).accessibilityHidden(true)
                Text(localized(rating.provider.titleKey)).font(DSFont.caption.weight(.semibold))
                Text(rating.valueText + "/10").font(DSFont.footnote.weight(.bold)).monospacedDigit()
            }
            if !compact {
                Text(localized(rating.origin == .tmdbAPI ? "由 TMDB 提供" : "由片源提供"))
                    .font(DSFont.caption2).foregroundStyle(.secondary)
                if let count = rating.voteCount {
                    Text(String(format: localized("%d 人评分"), count))
                        .font(DSFont.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("movie.rating." + rating.provider.rawValue)
    }
}
