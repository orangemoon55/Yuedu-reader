import SwiftUI

/// Async preview updates invalidate this leaf, not the Form's navigation/sheet/Save owners.
struct HomeSectionPreviewPane: View {
    @ObservedObject var model: HomeModel
    let page: HomePage
    let hiddenFromLatest: Set<SourceInstanceKey>
    let languages: ReadingLanguagePreferences
    let active: Bool
    @EnvironmentObject private var store: BookStore

    var body: some View {
        content
            .environment(\.homeRankPreview, true)
            .task(id: [AnyHashable(page), AnyHashable(hiddenFromLatest), AnyHashable(active)]) {
                guard active else { return }
                await model.syncPreview(with: page, hiddenFromLatest: hiddenFromLatest)
                guard !Task.isCancelled, active else { return }
                for row in model.rows { model.load(row.id) }
            }
    }

    @ViewBuilder private var content: some View {
        if page.sections.first?.binding == .aiRecommendations {
            AIRecommendationRow(section: HomeSection(layout: page.sections.first?.layout ?? .row,
                                                     binding: .aiRecommendations),
                                title: localized("AI 推薦"), canGenerate: false, open: { _, _ in })
        } else if !model.isReady {
            ProgressView().frame(maxWidth: .infinity)
        } else if let group = model.groups(in: nil, languages: languages).first, !group.isSettledEmpty {
            HomeRowView(group: group, content: content(of: group),
                        load: { for row in group.rows { model.load(row.id) } },
                        request: { for row in group.rows { if case .failed = row.state { model.request(row.id) } } },
                        open: { _, _ in }, openLocation: { _ in })
        } else {
            Text(localized("此目錄沒有內容"))
                .font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                .frame(maxWidth: .infinity)
        }
    }

    private func content(of group: HomeSectionGroup) -> HomeRowContent? {
        guard case .loaded(let entries) = group.state else { return nil }
        return HomeRowContent(entries: entries, store: store, withLists: group.section.layout.style == .chart)
    }
}
