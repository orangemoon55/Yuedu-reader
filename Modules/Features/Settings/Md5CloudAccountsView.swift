import SwiftUI

/// Native source picker for the existing credential editor. Does not contact/activate a bundle
/// on arrival; the detail page asks the reader to explicitly start the selected source first.
struct Md5CloudAccountsView: View {
    @ObservedObject var library: Md5SourceLibrary
    var body: some View {
        Form {
            Section {
                if library.sources.isEmpty {
                    Text(localized("請先在貓源頁加入一個來源，再配置該來源的網盤帳號。"))
                        .foregroundStyle(DSColor.textSecondary)
                }
                ForEach(library.sources) { source in
                    NavigationLink {
                        Md5SourceDetailView(source: source, library: library, opensAccounts: true)
                    } label: {
                        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                            Text(source.title).foregroundStyle(DSColor.textPrimary)
                            Text(source.host).font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                        }
                    }
                    .accessibilityIdentifier("md5source.accounts.\(source.id.prefix(8))")
                }
            } header: { Text(localized("選擇貓源")) } footer: {
                Text(localized("網盤帳號由所選貓源的配置中心管理。選擇後需明確啟動來源；只有啟動成功才會進入既有帳號編輯頁。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()
        }
        .softScrollEdges()
        .navigationTitle(localized("網盤帳號配置"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
        .task { library.loadIfNeeded() }
        .accessibilityIdentifier("md5source.accountsPicker")
    }
}
