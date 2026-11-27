import SwiftUI

/// Storage sections shown inline in Settings. Dialogs and lifecycle work are
/// hosted on the Form by `storageSpaceHost`, since iOS dismisses Section-hosted
/// presentations when the List re-renders.
@MainActor
struct StorageSpaceSections: View {
    @ObservedObject var model: StorageSpaceModel
    @Binding var pendingDeletion: StorageItem?
    var automaticLimitMB: Int?
    let onManageDownloads: () -> Void
    @EnvironmentObject private var settings: SettingsManager

    var body: some View {
        Group {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.control) {
                    if let capacity = model.snapshot?.device {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(deviceName).font(Theme.Typography.cardTitle)
                                Spacer()
                                capacityText(capacity)
                            }
                            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                                Text(deviceName).font(Theme.Typography.cardTitle)
                                capacityText(capacity)
                            }
                        }
                        StorageCapacityBar(capacity: capacity, appBytes: model.snapshot?.appBytes ?? 0)
                    } else if model.isLoading {
                        HStack { ProgressView(); Text("正在计算存储空间…").foregroundStyle(.secondary) }
                    } else {
                        Text("暂时无法读取设备容量").foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, Theme.Spacing.tight)

                LabeledContent {
                    Text(model.snapshot.map { format($0.appBytes) } ?? "—")
                        .font(Theme.Typography.body.weight(.semibold)).monospacedDigit()
                } label: {
                    Label(model.snapshot?.partial == true ? String(localized: "已统计的 Coda 占用") : String(localized: "Coda 占用"),
                          systemImage: "internaldrive")
                }

                Button(action: onManageDownloads) {
                    HStack {
                        Label("已下载", systemImage: "arrow.down.circle")
                        Spacer()
                        Text(size(.downloads)).foregroundStyle(.secondary).monospacedDigit()
                        DisclosureChevron()
                    }
                    .foregroundStyle(.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("storageManageDownloads")

                ForEach(StorageItem.visible, id: \.self) { item in
                    itemRow(item)
                }

                #if os(macOS)
                LabeledContent {
                    Picker("歌曲缓存上限", selection: $settings.audioCacheLimit) {
                        Text("512 MB").tag(Int64(512) << 20)
                        Text("2 GB").tag(Int64(2) << 30)
                        Text("8 GB").tag(Int64(8) << 30)
                        Text("不限").tag(Int64(0))
                    }
                    .labelsHidden()
                    .fixedSize()
                } label: {
                    Label("歌曲缓存上限", systemImage: "slider.horizontal.3")
                }
                #else
                Toggle(isOn: $settings.enableAudioCache) {
                    Label("歌曲缓存", systemImage: "slider.horizontal.3")
                }
                if settings.enableAudioCache {
                    Picker(selection: cacheLimitSelection) {
                        if let automaticLimitMB {
                            Text("自动（\(format(Int64(automaticLimitMB) * 1_000_000))）").tag(0)
                        } else {
                            Text("自动").tag(0)
                        }
                        ForEach(manualCacheLimitsMB, id: \.self) { megabytes in
                            Text(format(Int64(megabytes) * 1_000_000)).tag(megabytes)
                        }
                    } label: {
                        Label("上限", systemImage: "arrow.up.to.line")
                    }
                }
                #endif

                if let message = model.message ?? (model.snapshot?.partial == true ? String(localized: "部分存储信息不可用") : nil) {
                    Text(message).font(Theme.Typography.caption).foregroundStyle(.secondary).accessibilityAddTraits(.updatesFrequently)
                }
            } header: {
                Text("存储空间")
            } footer: {
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    if let other = model.snapshot?.otherAccountDownloads, other > 0 {
                        Text("其他账号的下载占用 \(format(other))。")
                    }
                    Text("可删除的项目会在需要时重新获取或生成；最近 10 分钟内写入的歌曲与临时文件会暂时保留。账号资料在退出登录后删除，下载索引随已下载歌曲一同删除。")
                }
                .font(Theme.Typography.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var busy: Bool { model.isLoading || model.isClearing }
    #if os(iOS)
    /// Tag 0 is the automatic limit; the rest are megabytes.
    private var cacheLimitSelection: Binding<Int> {
        Binding(get: { settings.audioCacheAutomatic ? 0 : settings.audioCacheSizeMB },
                set: { value in
                    if value == 0 { settings.audioCacheAutomatic = true }
                    else { settings.audioCacheAutomatic = false; settings.audioCacheSizeMB = value }
                })
    }
    private var manualCacheLimitsMB: [Int] {
        var sizes = [500, 1_000, 2_000, 5_000, 10_000]
        // A size chosen on the old slider stays selectable until it is changed.
        if !settings.audioCacheAutomatic, !sizes.contains(settings.audioCacheSizeMB) {
            sizes.append(settings.audioCacheSizeMB)
            sizes.sort()
        }
        return sizes
    }
    #endif
    private var deviceName: String {
        #if os(macOS)
        return "Mac"
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }
    private func size(_ category: StorageCategory) -> String {
        guard let snapshot = model.snapshot, !snapshot.unavailableCategories.contains(category) else { return "—" }
        return format(snapshot[category])
    }
    private func format(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    private func capacityText(_ capacity: DeviceStorageCapacity) -> some View {
        Text("已用 \(format(capacity.used))，共 \(format(capacity.total))")
            .font(Theme.Typography.secondary).foregroundStyle(.secondary).monospacedDigit()
    }
    private func bytes(_ item: StorageItem) -> Int64? {
        guard let snapshot = model.snapshot else { return nil }
        switch item {
        case .cache(let category):
            return snapshot.unavailableCategories.contains(category) ? nil : snapshot[category]
        case .appData(let kind):
            return snapshot.unavailableCategories.contains(.appData) ? nil : snapshot.appData[kind] ?? 0
        }
    }
    private func isClearing(_ item: StorageItem) -> Bool {
        switch item {
        case .cache(let category): model.clearingCategory == category
        case .appData(let kind): model.clearingAppData == kind
        }
    }
    private func itemRow(_ item: StorageItem) -> some View {
        let size = bytes(item)
        return HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.control) {
            // The detail sits in the label title so it aligns under the title, not the icon.
            Label {
                VStack(alignment: .leading, spacing: Theme.Spacing.micro) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.title)
                        Spacer()
                        Text(size.map(format) ?? "—").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Text(item.detail)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: item.icon)
            }
            if item.isDeletable {
                if isClearing(item) {
                    ProgressView().controlSize(.small)
                } else {
                    Button("删除", role: .destructive) { pendingDeletion = item }
                        .buttonStyle(.borderless)
                        .disabled(busy || (size ?? 0) == 0)
                        .accessibilityLabel(Text("删除\(item.title)"))
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Hosts the storage deletion dialog and refresh work on the enclosing Form.
@MainActor
private struct StorageSpaceHost: ViewModifier {
    @ObservedObject var model: StorageSpaceModel
    @Binding var pendingDeletion: StorageItem?
    @Binding var automaticLimitMB: Int?
    @EnvironmentObject private var settings: SettingsManager
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .confirmationDialog(pendingDeletion.map { String(localized: "删除\($0.title)？") } ?? "",
                                isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                                titleVisibility: .visible, presenting: pendingDeletion) { item in
                Button("删除", role: .destructive) { Task { await model.clear(item) } }
                Button("取消", role: .cancel) {}
            } message: { item in
                Text(item.detail)
            }
            .task(id: scenePhase) {
                if scenePhase == .active, !model.isClearing {
                    await model.reload()
                }
            }
            #if os(macOS)
            .onChange(of: settings.audioCacheLimit) { _, _ in
                Task { await model.reload() }
            }
            #else
            .task(id: [settings.enableAudioCache ? (settings.audioCacheAutomatic ? -1 : settings.audioCacheSizeMB) : 0]) {
                guard settings.enableAudioCache else { await DownloadManager.shared.refreshCachedTracks(); return }
                let limit = await settings.effectiveAudioCacheSizeMB(refresh: true)
                automaticLimitMB = settings.audioCacheAutomatic ? limit : nil
                try? await AudioCache.shared.enforce(maximumSizeMB: limit)
                await DownloadManager.shared.refreshCachedTracks()
                await model.reload()
            }
            #endif
    }
}

extension View {
    func storageSpaceHost(model: StorageSpaceModel, pendingDeletion: Binding<StorageItem?>,
                          automaticLimitMB: Binding<Int?>) -> some View {
        modifier(StorageSpaceHost(model: model, pendingDeletion: pendingDeletion, automaticLimitMB: automaticLimitMB))
    }
}

extension StorageItem {
    var title: String {
        switch self {
        case .cache(.imageCache): String(localized: "图片缓存")
        case .cache: String(localized: "歌曲缓存")
        case .appData(let kind): kind.title
        }
    }

    var detail: String {
        switch self {
        case .cache(.imageCache): String(localized: "浏览时加载的封面与图片。删除后保留已下载歌曲的封面。")
        case .cache: String(localized: "暂存最近播放的歌曲，包括汽水音乐解密后的音频，不含已下载音乐。")
        case .appData(let kind): kind.detail
        }
    }

    var icon: String {
        switch self {
        case .cache(.imageCache): "photo.on.rectangle"
        case .cache: "music.note"
        case .appData(let kind): kind.icon
        }
    }
}

extension AppDataKind {
    var title: String {
        switch self {
        case .temporary: String(localized: "临时文件")
        case .library: String(localized: "歌单与曲库快照")
        case .networkCache: String(localized: "网络缓存")
        case .analysis: String(localized: "音频分析")
        case .models: String(localized: "人声分离模型")
        case .diagnostics: String(localized: "诊断记录")
        case .offlineIndex: String(localized: "下载索引")
        case .account: String(localized: "账号资料")
        case .application: String(localized: "应用本体")
        case .other: String(localized: "设置与其他")
        }
    }

    var detail: String {
        switch self {
        case .temporary: String(localized: "未完成或中断的网络下载、上传等临时文件，可放心删除。")
        case .library: String(localized: "已打开歌单与平台曲库目录的本地副本，用于加快加载和离线浏览。删除后联网时重新获取。")
        case .networkCache: String(localized: "系统保存的接口响应。删除后部分页面首次加载会稍慢。")
        case .analysis: String(localized: "自动混音为播放过的歌曲计算的节拍与响度分析。删除后在需要时重新分析。")
        case .models: String(localized: "已停用的增强过渡曾下载的模型文件，可放心删除。")
        case .diagnostics: String(localized: "播放过渡采样、调试记录与登录诊断，仅用于排查问题。")
        case .offlineIndex: String(localized: "已下载歌曲的索引、歌词与封面，删除下载时一并移除。")
        case .account: String(localized: "登录凭据、账号信息与设备标识，退出登录后删除。")
        case .application: String(localized: "Coda 程序本身，卸载应用后释放。")
        case .other: String(localized: "偏好设置、播放队列与系统生成的启动快照。")
        }
    }

    var icon: String {
        switch self {
        case .temporary: "clock.arrow.circlepath"
        case .library: "music.note.list"
        case .networkCache: "network"
        case .analysis: "waveform"
        case .models: "cpu"
        case .diagnostics: "stethoscope"
        case .offlineIndex: "list.bullet.rectangle"
        case .account: "person.crop.circle"
        case .application: "app"
        case .other: "gearshape"
        }
    }
}
