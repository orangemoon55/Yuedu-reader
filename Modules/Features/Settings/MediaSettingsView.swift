import Foundation
import SwiftUI

/// Music preferences; source management stays in the music destination.
struct MediaSettingsView: View {
    enum Area {
        case music

        var title: String {
            switch self {
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
    @AppStorage(MediaPreferences.musicDefaultRateKey) private var musicDefaultRate = 1.0
    @AppStorage(MediaPreferences.musicResumeEnabledKey) private var musicResumeEnabled = true
    @AppStorage(MediaPreferences.musicLoopCurrentKey) private var musicLoopCurrent = false
    @AppStorage(MediaPreferences.musicArtworkSquareKey) private var musicArtworkSquare = true

    init(area: Area) {
        self.area = area
    }

    var body: some View {
        Form {
            switch area {
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

        .onChange(of: musicDefaultRate) { _, value in
            let clamped = Double(MediaPreferences.musicDefaultRate(in: .standard))
            if value != clamped { musicDefaultRate = clamped }
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
            Text(localized("音乐来源请在音乐页的来源设置中管理；网络与快取使用既有设定页。"))
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

    private func rateText(_ value: Double) -> String {
        String(format: "%.2f×", value)
    }

    private var musicPlaybackPendingHint: String {
        localized("已保存；待相容音乐播放器与来源接入后启用")
    }

    private func normalizeStoredValues() {
        let musicRate = Double(MediaPreferences.musicDefaultRate(in: .standard))
        if musicDefaultRate != musicRate { musicDefaultRate = musicRate }
    }
}

#Preview("音乐") {
    NavigationStack {
        MediaSettingsView(area: .music)
    }
    .environmentObject(BookStore())
}
