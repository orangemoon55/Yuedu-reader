import Observation
import SwiftUI

/// A retained request, not a transient notification: actions still arrive if Explore
/// has not been mounted or the source library is finishing its first read.
@MainActor @Observable
final class HomePageSettingsNavigation {
    struct Request: Identifiable, Equatable {
        let id = UUID()
        let action: ExploreMoreAction
    }
    var request: Request?
    func open(_ action: ExploreMoreAction) { request = Request(action: action) }
    func consume(_ id: UUID) {
        guard request?.id == id else { return }
        request = nil
    }
}

struct HomePageSettingsView: View {
    @Environment(HomePageSettingsNavigation.self) private var navigation

    var body: some View {
        List {
            Section {
                Button { navigation.open(.editHome) } label: {
                    Label(localized("編輯首頁"), systemImage: "pencil")
                }
                .accessibilityIdentifier("homeSettings.editHome")
                NavigationLink {
                    AggregationSettingsView()
                } label: {
                    Label(localized("中繼資料語言偏好推薦"), systemImage: "globe")
                }
                .accessibilityIdentifier("homeSettings.readingLanguages")
                NavigationLink {
                    List { AggregationDataSourcesSection() }
                        .navigationTitle(localized("數據來源"))
                        .themedAppSurface(for: .settings)
                } label: {
                    Label(localized("參與聚合的來源"), systemImage: "square.stack.3d.up")
                }
                .accessibilityIdentifier("homeSettings.sources")
                Button { navigation.open(.refresh) } label: {
                    Label(localized("重新整理"), systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("homeSettings.refresh")
                Button { navigation.open(.browser) } label: {
                    Label(localized("瀏覽器"), systemImage: "safari")
                }
                .accessibilityIdentifier("homeSettings.browser")
            }
            .foregroundStyle(DSColor.textPrimary)
            .interfaceSectionSurface()
        }
        .navigationTitle(localized("首頁設定"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
        .hidesRootTabBar()
        .accessibilityIdentifier("homeSettings.page")
    }
}
