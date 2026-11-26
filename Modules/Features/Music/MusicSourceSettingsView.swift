import SwiftUI
import UniformTypeIdentifiers

/// The only source-import surface. There are intentionally no CatVod, direct URL, audio,
/// playlist-file, or remote-script-URL import controls here.
struct MusicSourceSettingsView: View {
    @Binding var selectedSourceID: String
    @Binding var quality: String
    @ObservedObject private var store = MusicJSSourceStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var busy = false
    @State private var failure: String?
    @State private var task: Task<Void, Never>?
    @State private var generation = UUID()
    private var source: MusicJSSource? { store.sources.first { $0.id == selectedSourceID } }
    private var qualities: [String] { MusicCatalogResolverMapping.qualities(source: source) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(localized(MusicPublicCatalog.providerName), systemImage: "music.note.list")
                    Text(localized("首页排行榜、公开热门歌单及搜寻由独立目录提供，不依赖 JS 音源是否宣告 search。此目录不提供音讯网址，也不代表播放授权。"))
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text(localized("音乐目录")) }
                Section(header: Text(localized("播放解析")), footer: Text(localized("只可导入可信的 LX 格式 .js 档案。脚本可存取其音乐服务；Readcc 不会绕过付费、登入或 DRM 限制。"))) {
                    Button { importing = true } label: { Label(localized("导入 JS 音源"), systemImage: "square.and.arrow.down") }
                        .disabled(busy).accessibilityIdentifier("mediaHub.music.importJS")
                    if store.sources.isEmpty { Text(localized("尚未导入 JS 音源；仍可浏览与搜寻公开目录。")) .foregroundStyle(.secondary) }
                    else {
                        Picker(localized("JS 音源"), selection: $selectedSourceID) {
                            ForEach(store.sources) { Text($0.name).tag($0.id) }
                        }.accessibilityIdentifier("mediaHub.music.sourcePicker")
                        HStack {
                            Text(localized("解析平台"))
                            Spacer()
                            Text(localized("自动匹配歌曲平台")).foregroundStyle(.secondary)
                        }.accessibilityIdentifier("mediaHub.music.automaticProvider")
                        Text(localized("根据每首歌曲的原平台自动解析，仅使用当前 JS 音源；不支持的平台会提示，不会混用歌曲 ID。"))
                            .font(.footnote).foregroundStyle(.secondary)
                        if !qualities.isEmpty {
                            Picker(localized("音质"), selection: $quality) {
                                Text(localized("自动优先高音质")).tag(MusicQualityPolicy.automatic)
                                ForEach(MusicQualityPolicy.ordered(qualities), id: \.self) { Text($0).tag($0) }
                            }
                            Text(localized("自动模式优先请求歌曲原平台声明的高音质；手动档位不可用时优先选择较低档位。档位不代表实测码率或无损，实际音质取决于音源和输出设备。"))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if busy { ProgressView(localized("导入中…")) }
                }
                if !store.sources.isEmpty {
                    Section(localized("管理音源")) {
                        ForEach(store.sources) { source in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.name).font(.headline)
                                Text(source.version + " · " + source.providers.map(\.name).joined(separator: " / "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }.swipeActions {
                                Button(localized("移除"), role: .destructive) {
                                    do { try store.remove(source) }
                                    catch { failure = error.localizedDescription }
                                }
                            }
                        }
                    }
                }
                if let error = store.loadFailure { Text(error).foregroundStyle(.secondary) }
            }
            .navigationTitle(localized("音乐设置")).toolbarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(localized("完成")) { dismiss() } } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "js") ?? .javaScript],
                          allowsMultipleSelection: false, onCompletion: importSource)
            .alert(localized("音乐导入失败"), isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button(localized("关闭"), role: .cancel) { failure = nil }
            } message: { Text(failure ?? "") }
        }
        .onDisappear { task?.cancel(); generation = UUID() }
    }

    private func importSource(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure(let error) = result, (error as NSError).code != CocoaError.userCancelled.rawValue {
                failure = error.localizedDescription
            }
            return
        }
        task?.cancel(); let token = UUID(); generation = token; busy = true
        task = Task { @MainActor in
            defer { if generation == token { busy = false } }
            do {
                let source = try await store.importFile(url)
                guard !Task.isCancelled, generation == token else { return }
                selectedSourceID = source.id
                quality = MusicQualityPolicy.automatic
            } catch {
                guard !Task.isCancelled, generation == token else { return }
                failure = error.localizedDescription
            }
        }
    }
}
