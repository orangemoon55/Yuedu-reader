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
            case .video: return localized("影視設定")
            case .music: return localized("音樂設定")
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
                SettingsRowLabel(localized("播放內核"), systemImage: "play.rectangle")
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("media.video.kernel")

            SettingsSliderRow(
                title: localized("預設播放速度"),
                systemImage: "speedometer",
                valueText: rateText(videoDefaultRate),
                value: $videoDefaultRate,
                range: 0.5...3.0,
                step: 0.25
            )
            .accessibilityIdentifier("media.video.defaultRate")

            Toggle(isOn: $videoResumeEnabled) {
                SettingsRowLabel(localized("續播上次進度"), systemImage: "arrow.uturn.forward.circle")
            }
            .accessibilityIdentifier("media.video.resumeEnabled")
        } header: {
            Text(localized("播放"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("內核選擇於下次播放生效。自動模式可在 KSPlayer 無法使用或開啟失敗時改用 AVFoundation；強制 KSPlayer 失敗時會顯示錯誤，不會靜默切換。AVFoundation 只使用系統播放器。預設速度與續播偏好沿用既有播放進度保存與恢復。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()

        Section {
            Picker(selection: $videoPosterColumns) {
                ForEach(2...5, id: \.self) { columns in
                    Text(String(columns)).tag(columns)
                }
            } label: {
                SettingsRowLabel(localized("影視海報欄數"), systemImage: "square.grid.2x2")
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("media.video.posterColumns")

            Toggle(isOn: $videoShowsFacts) {
                SettingsRowLabel(localized("顯示影片資料行"), systemImage: "text.alignleft")
            }
            .accessibilityIdentifier("media.video.showsFacts")

            Picker(selection: $videoCardDensity) {
                Text(localized("舒適")).tag(MediaVideoCardDensity.comfortable)
                Text(localized("緊湊")).tag(MediaVideoCardDensity.compact)
            } label: {
                SettingsRowLabel(localized("卡片間距"), systemImage: "rectangle.grid.1x2")
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("media.video.cardDensity")
        } header: {
            Text(localized("影視佈局"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("套用於影視首頁、分類、站點列表與搜尋，並即時更新。預設固定三欄，海報維持 2:3；欄數不隨螢幕寬度自動切換，不影響已收藏媒體庫或音樂。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()

        Section {
            Picker(selection: $posterColumns) {
                ForEach(2...5, id: \.self) { columns in
                    Text(String(columns)).tag(columns)
                }
            } label: {
                SettingsRowLabel(localized("媒體庫海報欄數"), systemImage: "square.grid.2x2")
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("media.home.posterColumns")

            Toggle(isOn: $homeShowsContinue) {
                SettingsRowLabel(localized("顯示繼續觀看"), systemImage: "play.circle")
            }
            .disabled(true)
            .accessibilityValue(localized("待接線：目前只有書籤，尚無繼續觀看歷史"))
            .accessibilityIdentifier("media.home.showsContinue")
        } header: {
            Text(localized("已收藏影視"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("此欄數僅套用於已收藏影視媒體庫，不影響影視首頁、分類與搜尋。繼續觀看尚無播放歷史資料，暫停使用。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()

        Section {
            capabilityRow(title: localized("已實作"), detail: localized("播放內核選擇、速度與續播；影視固定欄數、資料行、間距與媒體庫獨立欄數"), systemImage: "checkmark.circle")
            capabilityRow(title: localized("待接線"), detail: localized("繼續觀看：目前只有書籤資料，尚無繼續觀看歷史列表"), systemImage: "clock")
            capabilityRow(title: localized("未提供"), detail: localized("本頁不提供字幕、彈幕供應器或未實作的畫質／解析兼容開關"), systemImage: "minus.circle")
        } header: {
            Text(localized("能力範圍"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("影視來源、播放解析與中繼資料是分開的能力；本頁不繞過存取限制，也不把靜態資源字串當作執行時證據。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()

        Section {
            NavigationLink {
                TMDBSettingsView()
            } label: {
                SettingsRowLabel(localized("TMDB 評分與憑證"), systemImage: "star.leadinghalf.filled")
            }
            .accessibilityIdentifier("media.video.tmdbSettings")
        }
        .interfaceSectionSurface()
    }

    @ViewBuilder
    private var musicSections: some View {
        Section {
            SettingsSliderRow(
                title: localized("預設播放速度"),
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
                SettingsRowLabel(localized("續播上次進度"), systemImage: "arrow.uturn.forward.circle")
            }
            .disabled(true)
            .accessibilityHint(musicPlaybackPendingHint)
            .accessibilityIdentifier("media.music.resumeEnabled")

            Toggle(isOn: $musicLoopCurrent) {
                SettingsRowLabel(localized("單曲循環"), systemImage: "repeat.1")
            }
            .disabled(true)
            .accessibilityHint(musicPlaybackPendingHint)
            .accessibilityIdentifier("media.music.loopCurrent")
        } header: {
            Text(localized("播放"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("待播放器接入：目前沒有原生音樂播放器或音樂來源；此處只保留已保存的未來偏好，控件暫停使用，接入相容播放器後才會生效。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()

        Section {
            Toggle(isOn: $musicArtworkSquare) {
                SettingsRowLabel(localized("使用方形封面"), systemImage: "square.fill")
            }
            .accessibilityIdentifier("media.music.artworkSquare")
        } header: {
            Text(localized("音樂展示"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("已實作：方形封面偏好即時保存，並由音樂媒體庫讀取；獨立音樂首頁與播放器佈局尚未提供。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()

        Section {
            capabilityRow(title: localized("已實作"), detail: localized("方形封面偏好；播放偏好值可隔離保存"), systemImage: "checkmark.circle")
            capabilityRow(title: localized("待接線"), detail: localized("播放速度、續播與單曲循環：目前沒有相容的音樂播放器或來源"), systemImage: "clock")
            capabilityRow(title: localized("未提供"), detail: localized("本頁不提供歌詞供應器、音樂來源供應器或未實作的音質兼容開關"), systemImage: "minus.circle")
        } header: {
            Text(localized("能力範圍"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("音樂來源與中繼資料是分開的能力；本頁只保存原生偏好，不宣稱靜態 AOT 字串代表可達的執行時功能。"))
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
                SettingsRowLabel(localized("MD5 源與憑證"), systemImage: "shippingbox")
            }
            .accessibilityIdentifier("media.sources.md5")

            Button {
                showNetworkSettings = true
            } label: {
                SettingsRowLabel(localized("網路設定"), systemImage: "network")
            }
            .accessibilityIdentifier("media.sources.network")

            Button {
                showCacheManagement = true
            } label: {
                SettingsRowLabel(localized("快取管理"), systemImage: "externaldrive.fill")
            }
            .accessibilityIdentifier("media.sources.cache")
        } header: {
            Text(localized("來源與資料"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("來源匯入與來源內的 Cookie／憑證沿用既有 MD5 源頁，使用者資料只保存在本機；來源設定與中繼資料設定不混在一起。"))
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
        case .automatic: return localized("自動")
        case .ksPlayer: return localized("KSPlayer")
        case .avFoundation: return localized("AVFoundation")
        }
    }

    private func rateText(_ value: Double) -> String {
        String(format: "%.2f×", value)
    }

    private var musicPlaybackPendingHint: String {
        localized("已保存；待相容音樂播放器與來源接入後啟用")
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

#Preview("影視") {
    NavigationStack {
        MediaSettingsView(area: .video)
    }
    .environmentObject(BookStore())
}

#Preview("音樂") {
    NavigationStack {
        MediaSettingsView(area: .music)
    }
    .environmentObject(BookStore())
}
