import SwiftUI
import UIKit

/// MD5 源, kept apart from 模組's JSON modules (maintainer: 「導入md5源的位置放在模組裡，和json源區分開」).
/// A source here is a CatVod JS bundle + its `.md5`; the page lists what is installed, imports
/// from an address, and opens one source to run it and set its 網盤 Cookie.
struct Md5SourceManagerView: View {
    @ObservedObject var library: Md5SourceLibrary
    @State private var showsImport = false
    @State private var importAddress = ""
    @State private var pendingRemoval: Md5Source?
    @State private var failure: String?

    init(library: Md5SourceLibrary? = nil) {
        self.library = library ?? .shared
    }

    var body: some View {
        Form {
            Section {
                if library.sources.isEmpty {
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text(localized("还没有猫源"))
                            .foregroundStyle(DSColor.textPrimary)
                        Text(localized("按右上角的 + 加入 .js.md5 網址，例如 https://host/cat/index.js.md5。"))
                            .font(DSFont.footnote)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                    .padding(.vertical, DSSpacing.xs)
                } else {
                    ForEach(library.sources) { source in
                        NavigationLink {
                            Md5SourceDetailView(source: source, library: library)
                        } label: {
                            row(source)
                        }
                        .accessibilityIdentifier("md5source.row.\(source.id.prefix(8))")
                        .swipeActions {
                            Button(localized("移除"), role: .destructive) { pendingRemoval = source }
                        }
                    }
                }
                ForEach(library.failures, id: \.self) { folder in
                    Text(String(format: localized("無法讀取的 MD5 源：%@"), folder))
                        .font(DSFont.footnote)
                        .foregroundStyle(DSColor.textSecondary)
                }
            } header: {
                Text(localized("猫源列表")).foregroundStyle(DSColor.textSecondary)
            } footer: {
                Text(localized("MD5 源是 CatVod 的 JS 打包檔，與 JSON 模組分開存放；下載後會核對 .md5 校驗，執行時只在本機 Node 環境內跑。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()

            Section {
                NavigationLink {
                    Md5CloudAccountsView(library: library)
                } label: {
                    Label(localized("网盘帐号配置"), systemImage: "person.badge.key")
                }
                .accessibilityIdentifier("md5source.accounts")
                Button {
                    importAddress = ""
                    showsImport = true
                } label: {
                    Label(localized("从网址汇入猫源"), systemImage: "square.and.arrow.down")
                }
                Button {
                    let address = UIPasteboard.general.string ?? ""
                    guard address.utf8.count <= 8192 else { failure = localized("剪贴簿网址过长。"); return }
                    importAddress = address
                    showsImport = true
                } label: {
                    Label(localized("从剪贴簿汇入"), systemImage: "doc.on.clipboard")
                }
                .accessibilityIdentifier("md5source.clipboard")
            } footer: {
                Text(localized("仅支援现有 CatVod JS / .js.md5 网址汇入。帐号配置会先让你选择来源，明确启动后再开启该来源的配置中心；来源之间不共用登入资料。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()
        }
        .softScrollEdges()
        .navigationTitle(localized("猫源"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    importAddress = ""
                    showsImport = true
                } label: {
                    Image(systemName: "plus").accessibilityHidden(true)
                }
                .accessibilityLabel(localized("新增猫源"))
                .accessibilityIdentifier("md5source.add")
            }
        }
        .sheet(isPresented: $showsImport) {
            Md5SourceImportSheet(library: library, initialAddress: importAddress)
        }
        .confirmationDialog(pendingRemoval.map { String(format: localized("移除「%@」？"), $0.title) } ?? "",
                            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
                            titleVisibility: .visible) {
            Button(localized("移除"), role: .destructive) {
                guard let source = pendingRemoval else { return }
                do { try library.remove(source) } catch { failure = (error as? Md5SourceError)?.message ?? error.localizedDescription }
                pendingRemoval = nil
            }
            Button(localized("取消"), role: .cancel) {}
        }
        .alert(localized("操作失敗"), isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button(localized("確定"), role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
        .task { library.loadIfNeeded() }
    }

    private func row(_ source: Md5Source) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(source.title)
                .foregroundStyle(DSColor.textPrimary)
            HStack(spacing: DSSpacing.xs) {
                Text(source.host)
                Text(verbatim: "·")
                Text(Md5SourceImportModel.byteCount(source.byteCount))
                if source.isChecksumVerified {
                    Label(localized("MD5 已核對"), systemImage: "checkmark.seal.fill")
                        .labelStyle(.titleAndIcon)
                }
            }
            .font(DSFont.footnote)
            .foregroundStyle(DSColor.textSecondary)
        }
    }
}

/// 新增 MD5 源: read the address, show the checksum result, write only on confirm.
struct Md5SourceImportSheet: View {
    @ObservedObject var library: Md5SourceLibrary
    @StateObject private var model: Md5SourceImportModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    init(library: Md5SourceLibrary, initialAddress: String = "") {
        self.library = library
        let model = Md5SourceImportModel(library: library)
        model.address = initialAddress
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://host/cat/index.js.md5", text: $model.address)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($focused)
                        .onSubmit { Task { await model.fetch() } }
                        .accessibilityIdentifier("md5source.import.address")
                    TextField(localized("名稱（可留空）"), text: $model.title)
                        .accessibilityIdentifier("md5source.import.title")
                    Button {
                        focused = false
                        Task { await model.fetch() }
                    } label: {
                        Label(localized("讀取並核對 MD5"), systemImage: "arrow.down.circle")
                    }
                    .disabled(!model.canFetch)
                    .accessibilityIdentifier("md5source.import.load")
                } header: {
                    Text(localized("來源位址")).foregroundStyle(DSColor.textSecondary)
                } footer: {
                    Text(localized("會讀取同目錄的 index.js 與 index.js.md5；校驗不符不會寫入。"))
                        .dsSectionFooter()
                }
                .interfaceSectionSurface()

                content
            }
            .softScrollEdges()
            .navigationTitle(localized("新增猫源"))
            .toolbarTitleDisplayMode(.inline)
            .themedAppSurface(for: .settings)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark").accessibilityHidden(true) }
                        .accessibilityLabel(localized("關閉"))
                }
                if case .preview = model.phase {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { Task { await model.commit() } } label: { Image(systemName: "checkmark").accessibilityHidden(true) }
                            .accessibilityLabel(localized("加入猫源"))
                            .disabled(model.isLoading)
                            .accessibilityIdentifier("md5source.import.commit")
                    }
                }
            }
            .onChange(of: model.phase) { _, phase in
                if case .done = phase { dismiss() }
            }
            .onAppear { focused = true }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .done:
            EmptyView()
        case .loading, .installing:
            Section {
                HStack(spacing: DSSpacing.sm) {
                    ProgressView()
                    Text(model.phase == .installing ? localized("寫入中") : localized("下載並校驗中"))
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            .interfaceSectionSurface()
        case .preview(let preview):
            Section {
                LabeledContent(localized("名稱"), value: preview.title)
                LabeledContent(localized("大小"), value: Md5SourceImportModel.byteCount(preview.data.count))
                if preview.checksum.isEmpty {
                    LabeledContent(localized("MD5 校驗"), value: localized("未提供"))
                } else {
                    LabeledContent(localized("MD5 校驗"), value: localized("通過"))
                    Text(preview.checksum)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(DSColor.textSecondary)
                        .textSelection(.enabled)
                }
                LabeledContent(localized("打包檔"), value: preview.bundleAddress)
            } header: {
                Text(localized("已讀取")).foregroundStyle(DSColor.textSecondary)
            } footer: {
                Text(localized("确认后会存到「模组 → 猫源」，不会写进 JSON 模组。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()
        case .failed(let message):
            Section {
                Text(message).foregroundStyle(DSColor.warning)
            } header: {
                Text(localized("無法加入")).foregroundStyle(DSColor.textSecondary)
            }
            .interfaceSectionSurface()
        }
    }
}

/// One installed source: run it, see the sites it publishes, and open its 配置中心.
struct Md5SourceDetailView: View {
    let source: Md5Source
    @ObservedObject var library: Md5SourceLibrary
    var opensAccounts = false
    @ObservedObject private var runtime = CatVodRuntime.shared
    @State private var state: LoadState = .idle
    @State private var failure: String?

    enum LoadState: Equatable {
        case idle, loading, loaded([CatVodSite]), failed(String)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent(localized("名稱"), value: source.title)
                LabeledContent(localized("主機"), value: source.host)
                LabeledContent(localized("大小"), value: Md5SourceImportModel.byteCount(source.byteCount))
                LabeledContent(localized("MD5"), value: source.isChecksumVerified ? localized("已核對") : localized("未提供"))
                Text(source.bundleAddress)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(DSColor.textSecondary)
                    .textSelection(.enabled)
            } header: {
                Text(localized("來源")).foregroundStyle(DSColor.textSecondary)
            }
            .interfaceSectionSurface()

            Section {
                switch state {
                case .idle:
                    Button {
                        Task { await run() }
                    } label: {
                        Label(localized(opensAccounts ? "启动来源以配置网盘帐号" : "启动并读取站点"), systemImage: "play.circle")
                    }
                    .accessibilityIdentifier("md5source.detail.run")
                case .loading:
                    HStack(spacing: DSSpacing.sm) {
                        ProgressView()
                        Text(localized("Node 正在載入打包檔…")).foregroundStyle(DSColor.textSecondary)
                    }
                case .failed(let message):
                    Text(message).foregroundStyle(DSColor.warning)
                    Button { Task { await run() } } label: { Label(localized("重試"), systemImage: "arrow.clockwise") }
                case .loaded(let sites):
                    NavigationLink {
                        PanCookieSettingsView(source: source, sites: sites)
                    } label: {
                        Label(localized("配置中心 · 網盤 Cookie"), systemImage: "person.badge.key")
                    }
                    .disabled(runtime.activeSourceID != source.id)
                    Text(String(format: localized("已讀取 %d 個站點"), sites.count))
                        .font(DSFont.footnote)
                        .foregroundStyle(DSColor.textSecondary)
                }
            } header: {
                Text(localized("執行")).foregroundStyle(DSColor.textSecondary)
            } footer: {
                Text(localized("站點清單由打包檔的 /config 提供；網盤 Cookie 保存在這個源自己的資料夾，與其他源分開。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()

            if case .loaded(let sites) = state, !sites.isEmpty {
                Section {
                    ForEach(sites) { site in
                        NavigationLink {
                            CatVodSiteBrowserView(sourceID: source.id, site: site)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(site.name).foregroundStyle(DSColor.textPrimary)
                                    Text(site.key).font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(DSColor.textSecondary)
                                }
                                Spacer()
                                if site.searchable {
                                    Text(localized("可搜尋")).font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text(localized("站點")).foregroundStyle(DSColor.textSecondary)
                }
                .interfaceSectionSurface()
            }
        }
        .softScrollEdges()
        .navigationTitle(source.title)
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
        .alert(localized("操作失敗"), isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button(localized("確定"), role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }

    private func run() async {
        state = .loading
        do {
            let sites = try await CatVodRuntime.shared.activate(
                source: source,
                bundleURL: library.bundleURL(for: source),
                dataDirectory: library.dataDirectory(for: source))
            state = .loaded(sites)
        } catch {
            let message = (error as? CatVodRuntimeError)?.message ?? error.localizedDescription
            state = .failed(message)
            failure = message
        }
    }
}

extension Md5SourceImportModel {
    static func byteCount(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useKB]
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
