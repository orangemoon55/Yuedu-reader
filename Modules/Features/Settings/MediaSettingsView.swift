import Foundation
import SwiftUI

/// The two native settings destinations kept separate so movie and music controls remain easy
/// to find. Runtime code can consume the same values through `MediaPreferences`.
struct MediaSettingsView: View {
    enum Area {
        case video
        case music

        var title: String {
            switch self {
            case .video: return localized("影视设置")
            case .music: return localized("音乐设置")
            }
        }
    }

    let area: Area
    @EnvironmentObject private var store: BookStore
    @State private var showNetworkSettings = false
    @State private var showCacheManagement = false

    // AppStorage is deliberately used at the UI boundary. The shared typed API below the UI
    // remains the source for playback/home services, while these bindings refresh live.
    @AppStorage(MediaPreferences.videoDefaultRateKey) private var videoDefaultRate = 1.0
    @AppStorage(MediaPreferences.videoResumeEnabledKey) private var videoResumeEnabled = true
    @AppStorage(MediaPreferences.videoKernelKey) private var videoKernel = VideoKernelPreference.automatic
    @AppStorage(MediaPreferences.videoPosterColumnsKey) private var videoPosterColumns = 3
    @AppStorage(MediaPreferences.videoShowsFactsKey) private var videoShowsFacts = true
    @AppStorage(MediaPreferences.videoCardDensityKey) private var videoCardDensity = MediaVideoCardDensity.comfortable
    @AppStorage(MediaPreferences.musicDefaultRateKey) private var musicDefaultRate = 1.0
    @AppStorage(MediaPreferences.musicResumeEnabledKey) private var musicResumeEnabled = true
    @AppStorage(MediaPreferences.musicLoopCurrentKey) private var musicLoopCurrent = false
    @AppStorage(MediaPreferences.homeShowsContinueKey) private var homeShowsContinue = true
    @AppStorage(MediaPreferences.posterColumnsKey) private var posterColumns = 3
    @AppStorage(MediaPreferences.musicArtworkSquareKey) private var musicArtworkSquare = true

    init(area: Area) {
        self.area = area
    }

    var body: some View {
        Form {
            switch area {
            case .video:
                videoSections
            case .music:
                musicSections
            }

            sharedSourceSections
        }
        .softScrollEdges()
        .themedAppSurface(for: .settings)
        .navigationTitle(area.title)
        .toolbarTitleDisplayMode(.inline)
        .onAppear(perform: normalizeStoredValues)
        .onChange(of: videoDefaultRate) { _, value in
            let clamped = Double(MediaPreferences.videoDefaultRate(in: .standard))
            if value != clamped { videoDefaultRate = clamped }
        }
        .onChange(of: musicDefaultRate) { _, value in
            let clamped = Double(MediaPreferences.musicDefaultRate(in: .standard))
            if value != clamped { musicDefaultRate = clamped }
        }
        .onChange(of: videoPosterColumns) { _, value in
            let clamped = MediaPreferences.videoPosterColumns(in: .standard)
            if value != clamped { videoPosterColumns = clamped }
        }
        .onChange(of: posterColumns) { _, value in
            let clamped = MediaPreferences.posterColumns(in: .standard)
            if value != clamped { posterColumns = clamped }
        }
        .sheet(isPresented: $showNetworkSettings) {
            NetworkSettingsView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showCacheManagement) {
            CacheManagementView(service: CacheManagementService(coverOwner: store, retentionOwner: store))
        }
    }

    @ViewBuilder
    private var videoSections: some View {
        Section {
            Picker(selection: $videoKernel) {
                ForEach(VideoKernelPreference.allCases) { kernel in
                    Text(videoKernelTitle(kernel)).tag(kernel)
                }
            } label: {
                SettingsRowLabel(localized("播放内核"), systemImage: "play.rectangle")
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("media.video.kernel")

            SettingsSliderRow(
                title: localized("预设播放速度"),
                systemImage: "speedometer",
                valueText: rateText(videoDefaultRate),
                value: $videoDefaultRate,
                range: 0.5...3.0,
                step: 0.25
            )
            .accessibilityIdentifier("media.video.defaultRate")

            Toggle(isOn: $videoResumeEnabled) {
                SettingsRowLabel(localized("续播上次进度"), systemImage: "arrow.uturn.forward.circle")
            }
            .accessibilityIdentifier("media.video.resumeEnabled")
        } header: {
            Text(localized("播放"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("内核选择于下次播放生效。自动模式可在 KSPlayer 无法使用或打开失败时改用 AVFoundation；强制 KSPlayer 失败时会显示错误，不会静默切换。AVFoundation 只使用系统播放器。默认速度与续播偏好沿用现有播放进度保存与恢复。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()

        Section {
            Picker(selection: $videoPosterColumns) {
                ForEach(2...5, id: \.self) { columns in
                    Text(String(columns)).tag(columns)
                }
            } label: {
                SettingsRowLabel(localized("影视海报列数"), systemImage: "square.grid.2x2")
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("media.video.posterColumns")

            Toggle(isOn: $videoShowsFacts) {
                SettingsRowLabel(localized("显示影片资料行"), systemImage: "text.alignleft")
            }
            .accessibilityIdentifier("media.video.showsFacts")

            Picker(selection: $videoCardDensity) {
                Text(localized("舒适")).tag(MediaVideoCardDensity.comfortable)
                Text(localized("紧凑")).tag(MediaVideoCardDensity.compact)
            } label: {
                SettingsRowLabel(localized("卡片间距"), systemImage: "rectangle.grid.1x2")
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("media.video.cardDensity")
        } header: {
            Text(localized("影视布局"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("应用于影视首页、分类、站点列表与搜索，并实时更新。默认固定三列，海报保持 2:3；列数不随屏幕宽度自动切换，不影响已收藏媒体库或音乐。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()

        Section {
            Picker(selection: $posterColumns) {
                ForEach(2...5, id: \.self) { columns in
                    Text(String(columns)).tag(columns)
                }
            } label: {
                SettingsRowLabel(localized("媒体库海报列数"), systemImage: "square.grid.2x2")
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("media.home.posterColumns")

            Toggle(isOn: $homeShowsContinue) {
                SettingsRowLabel(localized("显示继续观看"), systemImage: "play.circle")
            }
            .disabled(true)
            .accessibilityValue(localized("尚未接入：目前只有书签，暂无继续观看历史"))
            .accessibilityIdentifier("media.home.showsContinue")
        } header: {
            Text(localized("已收藏影视"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("此列数仅应用于已收藏影视媒体库，不影响影视首页、分类与搜索。继续观看尚无播放历史数据，暂不可用。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()

        Section {
            capabilityRow(title: localized("已实现"), detail: localized("播放内核选择、速度与续播；影视固定列数、资料行、间距与媒体库独立列数"), systemImage: "checkmark.circle")
            capabilityRow(title: localized("待接线"), detail: localized("继续观看：目前只有书签资料，尚无继续观看历史列表"), systemImage: "clock")
            capabilityRow(title: localized("未提供"), detail: localized("本页不提供字幕、弹幕供应器或未实作的画质／解析兼容开关"), systemImage: "minus.circle")
        } header: {
            Text(localized("能力范围"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("影视来源、播放解析与中继资料是分开的能力；本页不绕过存取限制，也不把静态资源字串当作执行时证据。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()

        Section {
            NavigationLink {
                TMDBSettingsView()
            } label: {
                SettingsRowLabel(localized("TMDB 评分与凭证"), systemImage: "star.leadinghalf.filled")
            }
            .accessibilityIdentifier("media.video.tmdbSettings")
        }
        .interfaceSectionSurface()
    }

    @ViewBuilder
    private var musicSections: some View {
        Section {
            SettingsSliderRow(
                title: localized("预设播放速度"),
                systemImage: "speedometer",
                valueText: rateText(musicDefaultRate),
                value: $musicDefaultRate,
                range: 0.5...3.0,
                step: 0.25
            )
            .disabled(true)
            .accessibilityHint(musicPlaybackPendingHint)
            .accessibilityIdentifier("media.music.defaultRate")

            Toggle(isOn: $musicResumeEnabled) {
                SettingsRowLabel(localized("续播上次进度"), systemImage: "arrow.uturn.forward.circle")
            }
            .disabled(true)
            .accessibilityHint(musicPlaybackPendingHint)
            .accessibilityIdentifier("media.music.resumeEnabled")

            Toggle(isOn: $musicLoopCurrent) {
                SettingsRowLabel(localized("单曲循环"), systemImage: "repeat.1")
            }
            .disabled(true)
            .accessibilityHint(musicPlaybackPendingHint)
            .accessibilityIdentifier("media.music.loopCurrent")
        } header: {
            Text(localized("播放"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("待播放器接入：目前没有原生音乐播放器或音乐来源；此处只保留已保存的未来偏好，控件暂停使用，接入相容播放器后才会生效。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()

        Section {
            Toggle(isOn: $musicArtworkSquare) {
                SettingsRowLabel(localized("使用方形封面"), systemImage: "square.fill")
            }
            .accessibilityIdentifier("media.music.artworkSquare")
        } header: {
            Text(localized("音乐展示"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("已实作：方形封面偏好即时保存，并由音乐媒体库读取；独立音乐首页与播放器布局尚未提供。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()

        Section {
            capabilityRow(title: localized("已实现"), detail: localized("方形封面偏好；播放偏好值可隔离保存"), systemImage: "checkmark.circle")
            capabilityRow(title: localized("待接线"), detail: localized("播放速度、续播与单曲循环：目前没有相容的音乐播放器或来源"), systemImage: "clock")
            capabilityRow(title: localized("未提供"), detail: localized("本页不提供歌词供应器、音乐来源供应器或未实作的音质兼容开关"), systemImage: "minus.circle")
        } header: {
            Text(localized("能力范围"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("音乐来源与中继资料是分开的能力；本页只保存原生偏好，不宣称静态 AOT 字串代表可达的执行时功能。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    @ViewBuilder
    private var sharedSourceSections: some View {
        Section {
            NavigationLink {
                Md5SourceManagerView()
            } label: {
                SettingsRowLabel(localized("MD5 源与凭证"), systemImage: "shippingbox")
            }
            .accessibilityIdentifier("media.sources.md5")

            Button {
                showNetworkSettings = true
            } label: {
                SettingsRowLabel(localized("网络设置"), systemImage: "network")
            }
            .accessibilityIdentifier("media.sources.network")

            Button {
                showCacheManagement = true
            } label: {
                SettingsRowLabel(localized("快取管理"), systemImage: "externaldrive.fill")
            }
            .accessibilityIdentifier("media.sources.cache")
        } header: {
            Text(localized("来源与资料"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("来源汇入与来源内的 Cookie／凭证沿用既有 MD5 源页，使用者资料只保存在本机；来源设定与中继资料设定不混在一起。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    private func capabilityRow(title: String, detail: String, systemImage: String) -> some View {
        LabeledContent {
            Text(detail)
                .font(DSFont.caption)
                .foregroundStyle(DSColor.textSecondary)
                .multilineTextAlignment(.trailing)
        } label: {
            SettingsRowLabel(title, systemImage: systemImage)
        }
    }

    private func videoKernelTitle(_ kernel: VideoKernelPreference) -> String {
        switch kernel {
        case .automatic: return localized("自动")
        case .ksPlayer: return localized("KSPlayer")
        case .avFoundation: return localized("AVFoundation")
        }
    }

    private func rateText(_ value: Double) -> String {
        String(format: "%.2f×", value)
    }

    private var musicPlaybackPendingHint: String {
        localized("已保存；待相容音乐播放器与来源接入后启用")
    }

    private func normalizeStoredValues() {
        let videoRate = Double(MediaPreferences.videoDefaultRate(in: .standard))
        if videoDefaultRate != videoRate { videoDefaultRate = videoRate }

        let musicRate = Double(MediaPreferences.musicDefaultRate(in: .standard))
        if musicDefaultRate != musicRate { musicDefaultRate = musicRate }

        let videoColumns = MediaPreferences.videoPosterColumns(in: .standard)
        if videoPosterColumns != videoColumns { videoPosterColumns = videoColumns }

        let columns = MediaPreferences.posterColumns(in: .standard)
        if posterColumns != columns { posterColumns = columns }
    }
}

#Preview("影视") {
    NavigationStack {
        MediaSettingsView(area: .video)
    }
    .environmentObject(BookStore())
}

#Preview("音乐") {
    NavigationStack {
        MediaSettingsView(area: .music)
    }
    .environmentObject(BookStore())
}
