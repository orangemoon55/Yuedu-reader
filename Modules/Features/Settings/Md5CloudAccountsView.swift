import SwiftUI

/// Native source picker for the existing credential editor. Does not contact/activate a bundle
/// on arrival; the detail page asks the reader to explicitly start the selected source first.
struct Md5CloudAccountsView: View {
    @ObservedObject var library: Md5SourceLibrary
    var body: some View {
        Form {
            Section {
                if library.sources.isEmpty {
                    Text(localized("请先在猫源页加入一个来源，再配置该来源的网盘帐号。"))
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
            } header: { Text(localized("选择猫源")) } footer: {
                Text(localized("网盘帐号由所选猫源的配置中心管理。选择后需明确启动来源；只有启动成功才会进入既有帐号编辑页。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()
        }
        .softScrollEdges()
        .navigationTitle(localized("网盘帐号配置"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
        .task { library.loadIfNeeded() }
        .accessibilityIdentifier("md5source.accountsPicker")
    }
}
