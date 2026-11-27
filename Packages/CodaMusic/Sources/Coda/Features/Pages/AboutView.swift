import SwiftUI

/// Product information, updates, project links and notices, shown inline in
/// Settings. `licensesRoute` is pushed on the hosting stack, which differs per
/// platform; the disclaimer sheet is hosted on the Form by the caller.
struct AboutSections<LicensesRoute: Hashable>: View {
    let licensesRoute: LicensesRoute
    @Binding var showsDisclaimer: Bool
    private let info = AppAboutInfo()

    var body: some View {
        Section {
            AboutHeader(info: info)

            Group {
                LabeledContent { Text(info.version) } label: { Label("版本", systemImage: "number") }
                LabeledContent { Text(info.build) } label: { Label("构建号", systemImage: "hammer") }
                if let commit = info.commit {
                    LabeledContent { Text(commit) } label: { Label("提交", systemImage: "arrow.triangle.branch") }
                }
                LabeledContent { Text(info.developer) } label: { Label("开发者", systemImage: "person") }
            }
            .textSelection(.enabled)

            AboutUpdateRows()

            if let url = info.websiteURL {
                AboutLinkRow(title: "官网", systemImage: "globe", detail: AppAboutInfo.displayAddress(url), url: url)
            }
            if let url = info.repositoryURL {
                AboutLinkRow(title: "GitHub 仓库", systemImage: "chevron.left.forwardslash.chevron.right",
                             detail: info.repository, url: url)
            }
            if let url = info.issuesURL {
                AboutLinkRow(title: "问题反馈", systemImage: "exclamationmark.bubble", detail: nil, url: url)
            }
            if let url = info.releasesURL {
                AboutLinkRow(title: "版本发布", systemImage: "shippingbox", detail: nil, url: url)
            }

            NavigationLink(value: licensesRoute) {
                Label("开源许可与致谢", systemImage: "doc.text")
            }
            .pageFormNavigationRow()

            Button {
                showsDisclaimer = true
            } label: {
                Label("查看完整免责声明", systemImage: "exclamationmark.shield")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } header: {
            Text("关于")
        } footer: {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text("Coda 以 GNU AGPL v3.0 开源，使用并参考了多个开源项目。")
                Text("Coda 是非官方的第三方客户端，与各音乐平台无关。音乐内容与数据均来自当前选择的音乐平台，版权归原权利人所有。")
            }
        }
    }
}

private struct AboutUpdateRows: View {
    @EnvironmentObject private var settings: SettingsManager
    #if os(macOS)
    @ObservedObject private var updater = UpdaterManager.shared
    #endif

    var body: some View {
        Toggle(isOn: $settings.autoCheckUpdates) {
            Label("启动时自动检查更新", systemImage: "clock.arrow.circlepath")
        }
        Button {
            #if os(iOS)
            IOSUpdater.shared.check(interactive: true)
            #else
            updater.checkForUpdates()
            #endif
        } label: {
            Label("检查更新", systemImage: "arrow.triangle.2.circlepath")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .disabled(!updater.canCheckForUpdates)
        #endif
    }
}

private struct AboutHeader: View {
    let info: AppAboutInfo

    var body: some View {
        VStack(spacing: 10) {
            AppIconImage()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text(info.name)
                .font(.title2.bold())
            Text("多平台音乐客户端")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

private struct AppIconImage: View {
    var body: some View {
        #if os(macOS)
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .scaledToFit()
        #else
        if let icon = Self.primaryIcon {
            Image(uiImage: icon)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.tint)
        }
        #endif
    }

    #if os(iOS)
    private static let primaryIcon: UIImage? = {
        for key in ["CFBundleIcons", "CFBundleIcons~ipad"] {
            guard let icons = Bundle.main.object(forInfoDictionaryKey: key) as? [String: Any],
                  let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
                  let name = (primary["CFBundleIconFiles"] as? [String])?.last,
                  let image = UIImage(named: name) else { continue }
            return image
        }
        return nil
    }()
    #endif
}

private struct AboutLinkRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let detail: String?
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Label(title, systemImage: systemImage)
                Spacer(minLength: 8)
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(url.absoluteString))
    }
}

/// Coda's own licenses plus the acknowledgement index from ThirdPartyNotices.
struct OpenSourceLicensesView: View {
    private let info = AppAboutInfo()
    private let groups = BundledLegalDocument.thirdPartyNotices.text.map(ThirdPartyNotices.parse) ?? []
    @State private var document: BundledLegalDocument?
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Group {
                Section {
                    documentRow(.license, title: "Coda", license: "GNU AGPL v3.0")
                    documentRow(.copying, title: "GNU GPL v3.0", license: "LGPL 引用的通用条款")
                    documentRow(.thirdPartyNotices, title: "第三方声明", license: "完整的引用说明与修改记录")
                } header: {
                    Text("许可证")
                }

                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    Section(LocalizedStringKey(group.title)) {
                        ForEach(Array(group.entries.enumerated()), id: \.offset) { _, entry in
                            ProjectRow(entry: entry)
                        }
                    }
                }

                if groups.isEmpty, let url = info.fileURL("ThirdPartyNotices/README.md") {
                    Section("致谢") {
                        AboutLinkRow(title: "在 GitHub 查看第三方声明", systemImage: "doc.text.magnifyingglass", detail: nil, url: url)
                    }
                }

                Section {
                    Text("感谢以上开源项目及其作者。各项目的许可证以其仓库中的文本为准。")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .pageFormRows()
        }
        .pageFormStyle()
        .nativeTabBarScrolling()
        .navigationTitle("开源许可与致谢")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $document) { LegalDocumentSheet(document: $0) }
    }

    private func documentRow(_ doc: BundledLegalDocument, title: LocalizedStringKey, license: LocalizedStringKey) -> some View {
        Button {
            if doc.bundleURL != nil {
                document = doc
            } else if let url = info.fileURL(doc.rawValue) {
                openURL(url)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                    Text(license)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ProjectRow: View {
    let entry: ThirdPartyNoticeEntry

    var body: some View {
        if let url = entry.url {
            Link(destination: url) { content(showsArrow: true) }
                .buttonStyle(.plain)
        } else {
            content(showsArrow: false)
        }
    }

    private func content(showsArrow: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: entry.name)
                if let license = entry.license {
                    Text(LocalizedStringKey(license))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if showsArrow {
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct LegalDocumentSheet: View {
    let document: BundledLegalDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(verbatim: document.text ?? "")
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle(Text(verbatim: document.rawValue))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 520)
        #endif
    }
}
