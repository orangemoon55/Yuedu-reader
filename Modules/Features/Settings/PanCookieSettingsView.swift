import SwiftUI

/// 配置中心 · 網盤 Cookie: the bundle's own credential routes made native. Values are read from
/// `GET /website/api/credentials` of the active source and written with
/// `PUT /website/api/credential/<provider>/<field>`, exactly what its /website page does, so the
/// source's own bare requests share the login. Each source keeps its own folder and database.
struct PanCookieSettingsView: View {
    let source: Md5Source
    let sites: [CatVodSite]

    @State private var values: [String: [String: String]] = [:]
    @State private var isLoading = true
    @State private var loaded = false
    @State private var failure: String?
    @State private var savedProvider: String?
    @State private var isSaving = false

    private struct Provider: Identifiable {
        struct Field: Identifiable {
            let id: String
            let label: String
        }
        let id: String
        let title: String
        let fields: [Field]
    }

    private let providers: [Provider] = [
        Provider(id: "quark", title: "夸克網盤", fields: [.init(id: "cookie", label: "Cookie")]),
        Provider(id: "uc", title: "UC 網盤", fields: [.init(id: "cookie", label: "Cookie"),
                                                    .init(id: "token", label: "TV Token"),
                                                    .init(id: "refreshtoken", label: "TV Refresh Token")]),
        Provider(id: "baidu", title: "百度網盤", fields: [.init(id: "cookie", label: "Cookie")]),
        Provider(id: "pan115", title: "115 網盤", fields: [.init(id: "cookie", label: "Cookie")]),
        Provider(id: "pan123", title: "123 雲盤", fields: [.init(id: "account", label: "帳號"),
                                                       .init(id: "password", label: "密碼")]),
        Provider(id: "pan189", title: "天翼雲盤", fields: [.init(id: "cookie", label: "Cookie")]),
        Provider(id: "bili", title: "B 站", fields: [.init(id: "cookie", label: "Cookie")]),
    ]

    var body: some View {
        Form {
            if isLoading {
                Section {
                    HStack(spacing: DSSpacing.sm) {
                        ProgressView()
                        Text(localized("讀取已保存的登入…")).foregroundStyle(DSColor.textSecondary)
                    }
                }
                .interfaceSectionSurface()
            } else if !loaded {
                Section {
                    Button(localized("重试")) { Task { await load() } }
                        .accessibilityIdentifier("pan.retry")
                }.interfaceSectionSurface()
            } else {
                ForEach(providers) { provider in
                    Section {
                        ForEach(provider.fields) { field in
                            TextField(field.label, text: binding(provider.id, field.id), axis: .vertical)
                                .lineLimit(2...5)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(.footnote, design: .monospaced))
                                .accessibilityIdentifier("pan.\(provider.id).\(field.id)")
                        }
                        Button {
                            Task { await save(provider) }
                        } label: {
                            Label(savedProvider == provider.id ? localized("已保存") : localized("保存"),
                                  systemImage: savedProvider == provider.id ? "checkmark.circle.fill" : "square.and.arrow.down")
                        }
                        .disabled(isSaving)
                        .accessibilityIdentifier("pan.\(provider.id).save")
                    } header: {
                        Text(provider.title).foregroundStyle(DSColor.textSecondary)
                    } footer: {
                        Text(localized("只保存在這個 MD5 源自己的資料庫；清除請把欄位留空再保存。"))
                            .dsSectionFooter()
                    }
                    .interfaceSectionSurface()
                }
            }
        }
        .softScrollEdges()
        .navigationTitle(localized("配置中心"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
        .alert(localized("操作失敗"), isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button(localized("確定"), role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
        .task(id: source.id) { await load() }
    }

    private func binding(_ provider: String, _ field: String) -> Binding<String> {
        Binding(
            get: { values[provider]?[field] ?? "" },
            set: { newValue in
                var fields = values[provider] ?? [:]
                fields[field] = newValue
                values[provider] = fields
                savedProvider = nil
            })
    }

    private func load() async {
        isLoading = true
        loaded = false
        values = [:]
        defer { isLoading = false }
        do {
            let credentials = try await CatVodCatalog.shared.credentials(sourceID: source.id)
            try Task.checkCancellation()
            values = credentials.values
            loaded = true
        } catch {
            if !Task.isCancelled { failure = CatVodCatalog.message(error) }
        }
    }

    private func save(_ provider: Provider) async {
        isSaving = true
        defer { isSaving = false }
        do {
            for field in provider.fields {
                let value = values[provider.id]?[field.id] ?? ""
                if value.isEmpty {
                    try await CatVodCatalog.shared.clearCredential(sourceID: source.id, provider: provider.id, field: field.id)
                } else {
                    try await CatVodCatalog.shared.saveCredential(sourceID: source.id, provider: provider.id, field: field.id, value: value)
                }
            }
            savedProvider = provider.id
        } catch {
            failure = CatVodCatalog.message(error)
        }
    }
}
