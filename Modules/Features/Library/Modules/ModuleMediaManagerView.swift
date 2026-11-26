import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Genuine file/clipboard import and a persistent registry, not an advertised playback engine.
struct ModuleMediaManagerView: View {
    let kind: ModuleMediaRegistryKind
    @ObservedObject private var store = ModuleMediaImportStore.shared
    @State private var showsFile = false
    @State private var showsText = false
    @State private var fileAction: ImportAction = .automatic
    @State private var textIsSubtitle = false
    @State private var clipboardText = ""
    @State private var message: String?

    private enum ImportAction { case automatic, registry, subtitle }
    private var isSubtitle: Bool { kind == .subtitle }
    private var title: String { localized(isSubtitle ? "字幕" : "弹幕源") }
    private var sourceList: [ModuleRegisteredMediaSource] { store.sources(kind) }
    private var hasContent: Bool { !sourceList.isEmpty || (isSubtitle && !store.archive.files.isEmpty) }
    private var allowedTypes: [UTType] {
        let subtitleTypes = [UTType(filenameExtension: "srt") ?? .plainText, UTType(filenameExtension: "vtt") ?? .plainText]
        switch fileAction {
        case .registry: return [.json]
        case .subtitle: return subtitleTypes
        case .automatic: return isSubtitle ? [.json] + subtitleTypes : [.json]
        }
    }

    var body: some View {
        Form {
            if !hasContent {
                Section {
                    VStack(spacing: DSSpacing.md) {
                        Image(systemName: isSubtitle ? "captions.bubble" : "bubble.left.and.bubble.right")
                            .font(.system(size: 42)).foregroundStyle(DSColor.textSecondary).accessibilityHidden(true)
                        Text(localized(isSubtitle ? "还没有字幕" : "还没有弹幕源"))
                            .font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                        Text(localized(isSubtitle ? "可登记线上字幕源，或汇入本地 .srt / .vtt 字幕并预览。" : "可汇入弹弹 play 相容来源的 JSON 登记资料。"))
                            .font(DSFont.subheadline).foregroundStyle(DSColor.textSecondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, DSSpacing.xl)
                }.interfaceSectionSurface()
            }
            if let failure = store.loadFailure {
                Section { Text(failure).foregroundStyle(DSColor.warning) }.interfaceSectionSurface()
            }
            if !sourceList.isEmpty {
                Section {
                    ForEach(sourceList) { source in
                        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                            Text(source.name).font(DSFont.headline)
                            Text(source.baseUrl).font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                                .lineLimit(2).textSelection(.enabled)
                            Text(localized("仅登记，播放匹配尚未接入"))
                                .font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("moduleMedia.source.\(source.id)")
                        .swipeActions {
                            Button(localized("移除"), role: .destructive) { perform { try store.removeSource(id: source.id, kind: kind) } }
                        }
                    }
                } header: { Text(localized(isSubtitle ? "线上字幕源" : "弹幕源列表")) }
                .interfaceSectionSurface()
            }
            if isSubtitle && !store.archive.files.isEmpty {
                Section {
                    ForEach(store.archive.files) { file in
                        NavigationLink {
                            ModuleSubtitlePreviewView(file: file)
                        } label: {
                            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                                Text(file.title).foregroundStyle(DSColor.textPrimary)
                                Text("\(file.cues.count) \(localized("个时间轴")) · \(file.encoding)")
                                    .font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                            }
                        }
                        .accessibilityIdentifier("moduleMedia.subtitle.\(file.id)")
                        .swipeActions {
                            Button(localized("移除"), role: .destructive) { perform { try store.removeSubtitle(id: file.id) } }
                        }
                    }
                } header: { Text(localized("本地字幕")) }
                .interfaceSectionSurface()
            }
            Section {
                Button { pick(.registry) } label: {
                    Label(localized(isSubtitle ? "汇入线上字幕源（档案）" : "从文件导入"), systemImage: "square.and.arrow.down")
                }.accessibilityIdentifier("moduleMedia.import.registryFile")
                Button { paste(subtitle: false) } label: {
                    Label(localized(isSubtitle ? "汇入线上字幕源（剪贴簿）" : "从剪贴簿汇入"), systemImage: "doc.on.clipboard")
                }.accessibilityIdentifier("moduleMedia.import.registryClipboard")
                if isSubtitle {
                    Button { pick(.subtitle) } label: {
                        Label(localized("汇入本地字幕档案"), systemImage: "captions.bubble")
                    }.accessibilityIdentifier("moduleMedia.import.subtitleFile")
                    Button { paste(subtitle: true) } label: {
                        Label(localized("从剪贴簿汇入字幕文字"), systemImage: "doc.on.clipboard")
                    }.accessibilityIdentifier("moduleMedia.import.subtitleClipboard")
                }
            } header: { Text(localized("导入")) } footer: {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(localized(isSubtitle
                        ? "SubtitleDB 相容来源设定：UTF-8 JSON 物件或阵列，每项包含字串 id、name、baseUrl。本地字幕支援 .srt / .vtt（UTF-8 或 GBK），每档最多 4 MB。"
                        : "弹弹 play 相容来源：UTF-8 JSON 阵列，每项包含字串 id、name、baseUrl；最多 256 KB、100 个来源。同 id 再次汇入会更新登记。"))
                    Text(localized("仅登记来源与保存本地字幕，播放时的自动匹配、下载与字幕挂载尚未接入。不会在汇入时连线或执行脚本。"))
                }.dsSectionFooter()
            }.interfaceSectionSurface()
        }
        .softScrollEdges()
        .navigationTitle(title)
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { pick(.automatic) } label: { Image(systemName: "doc.badge.plus").accessibilityHidden(true) }
                    .accessibilityLabel(localized("导入"))
                    .accessibilityIdentifier("moduleMedia.import")
            }
        }
        .fileImporter(isPresented: $showsFile, allowedContentTypes: allowedTypes) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let local = fileAction == .subtitle || (fileAction == .automatic && url.pathExtension.lowercased() != "json")
                let data = try ModuleMediaImportStore.readBounded(url, limit: local ? ModuleMediaImportParser.subtitleByteLimit : ModuleMediaImportParser.registryByteLimit)
                try importData(data, filename: local ? url.lastPathComponent : nil)
            } catch { message = error.localizedDescription }
        }
        .sheet(isPresented: $showsText) {
            ModuleMediaTextImportSheet(isSubtitle: textIsSubtitle, initialText: clipboardText) { text, filename in
                try importData(Data(text.utf8), filename: textIsSubtitle ? filename : nil)
            }
        }
        .alert(localized("媒体汇入"), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(localized("确定"), role: .cancel) {}
        } message: { Text(message ?? "") }
        .task { store.loadIfNeeded() }
        .accessibilityIdentifier(isSubtitle ? "moduleMedia.subtitles" : "moduleMedia.danmaku")
    }

    private func pick(_ action: ImportAction) { fileAction = action; showsFile = true }

    private func paste(subtitle: Bool) {
        // Only access the clipboard after this explicit user action.
        let text = UIPasteboard.general.string ?? ""
        let limit = subtitle ? ModuleMediaImportParser.subtitleByteLimit : ModuleMediaImportParser.registryByteLimit
        guard text.utf8.count <= limit else { message = localized("剪贴簿内容超过汇入大小限制。"); return }
        textIsSubtitle = subtitle
        clipboardText = text
        showsText = true
    }

    private func importData(_ data: Data, filename: String?) throws {
        if let filename { try store.importSubtitle(data, filename: filename) }
        else { try store.importRegistry(data, kind: kind) }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { message = error.localizedDescription }
    }
}

private struct ModuleMediaTextImportSheet: View {
    let isSubtitle: Bool
    let onImport: (String, String) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var filename = "剪贴簿.srt"
    @State private var failure: String?

    init(isSubtitle: Bool, initialText: String, onImport: @escaping (String, String) throws -> Void) {
        self.isSubtitle = isSubtitle
        self.onImport = onImport
        _text = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            Form {
                if isSubtitle {
                    Section {
                        TextField(localized("档名（.srt 或 .vtt）"), text: $filename)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("moduleMedia.text.filename")
                    }.interfaceSectionSurface()
                }
                Section {
                    TextEditor(text: $text).frame(minHeight: 220)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel(localized(isSubtitle ? "字幕文字" : "来源 JSON"))
                        .accessibilityIdentifier("moduleMedia.text.content")
                } footer: {
                    Text(localized("确认后只保存至本机；不会自动连线或启用播放匹配。"))
                }.interfaceSectionSurface()
                if let failure { Section { Text(failure).foregroundStyle(DSColor.warning) }.interfaceSectionSurface() }
            }
            .navigationTitle(localized(isSubtitle ? "汇入字幕文字" : "汇入来源 JSON"))
            .toolbarTitleDisplayMode(.inline)
            .themedAppSurface(for: .settings)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(localized("取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("导入")) {
                        do { try onImport(text, filename); dismiss() } catch { failure = error.localizedDescription }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("moduleMedia.text.commit")
                }
            }
        }
    }
}

private struct ModuleSubtitlePreviewView: View {
    let file: ModuleLocalSubtitle
    var body: some View {
        List {
            Section {
                LabeledContent(localized("档案"), value: file.filename)
                LabeledContent(localized("编码"), value: file.encoding)
                Text(localized("已保存本地字幕；播放挂载与自动匹配尚未接入。"))
                    .font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
            }.interfaceSectionSurface()
            Section {
                ForEach(file.cues.indices, id: \.self) { index in
                    let cue = file.cues[index]
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text(String(format: "%.3f → %.3f s", cue.start, cue.end))
                            .font(.system(.caption, design: .monospaced)).foregroundStyle(DSColor.textSecondary)
                        Text(cue.text).textSelection(.enabled)
                    }.accessibilityElement(children: .combine)
                }
            } header: { Text(localized("时间轴预览")) }.interfaceSectionSurface()
        }
        .listStyle(.insetGrouped)
        .navigationTitle(file.title).toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
        .accessibilityIdentifier("moduleMedia.subtitlePreview")
    }
}
