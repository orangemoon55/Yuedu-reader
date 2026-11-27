import SwiftUI

/// Show the last resolved stream quality until the next stream resolves.
struct NowPlayingQualityControl: View {
    @EnvironmentObject private var player: PlayerService
    @EnvironmentObject private var account: AccountStore
    @ObservedObject private var settings = SettingsManager.shared
    @State private var qualities: [AudioQualityOption] = []
    @State private var externalQualities: [AudioQualityOption] = []
    @State private var loading = false
    @State private var failed = false

    private var currentQuality: AudioQuality? {
        player.servedQuality.flatMap(AudioQuality.init(rawValue:))
    }

    private var title: String {
        // KuGou can resolve a playable stream without reporting its encoding.
        // Keep the menu available without presenting the preference as fact.
        if player.audioQualityBadgeState == nil, player.currentTrack != nil {
            return String(localized: "音质")
        }
        switch player.audioQualityBadgeState {
        case .quality(let level):
            return AudioQuality(rawValue: level).map(qualityTitle) ?? String(localized: "音质")
        case .externalSource:
            return currentQuality.map(qualityTitle) ?? String(localized: "音质")
        case nil:
            return ""
        }
    }

    private func qualityTitle(_ quality: AudioQuality) -> String {
        account.provider == .qishui ? quality.displayName : AudioQualityOption.unifiedTitle(quality: quality)
    }

    private var badgeQuality: AudioQuality? {
        switch player.audioQualityBadgeState {
        case .quality(let level): return AudioQuality(rawValue: level)
        case .externalSource: return currentQuality
        case nil: return nil
        }
    }

    /// The track plays from another source, so the platform's tiers do not apply.
    private var playsExternalSource: Bool { player.unblockSource != nil }

    /// The serving source's own tiers once loaded; until then the served tier
    /// alone. The served tier always shows the stream actually playing.
    private var externalOptions: [AudioQualityOption] {
        var options = externalQualities
        if let currentQuality {
            let served = AudioQualityOption(quality: currentQuality, title: player.externalQualityTitle
                ?? AudioQualityOption.unifiedTitle(quality: currentQuality))
            if let index = options.firstIndex(where: { $0.quality == currentQuality }) {
                if player.externalQualityTitle != nil { options[index] = served }
            } else {
                options.append(served)
            }
        }
        return AudioQualityOption.unified(options)
    }

    private var options: [AudioQualityOption] {
        if playsExternalSource { return externalOptions }
        if account.provider == .qishui {
            var options = qualities
            if let currentQuality {
                let servedOption = player.servedQishuiQualityOption.flatMap { $0.quality == currentQuality ? $0 : nil }
                if let index = options.firstIndex(where: { $0.quality == currentQuality }) {
                    if let servedOption, options[index].title == currentQuality.displayName {
                        options[index] = servedOption
                    }
                } else {
                    options.append(servedOption ?? .init(quality: currentQuality, title: currentQuality.displayName))
                }
            }
            return options.sorted { (AudioQuality.allCases.firstIndex(of: $0.quality) ?? 0) < (AudioQuality.allCases.firstIndex(of: $1.quality) ?? 0) }
        }
        return AudioQualityOption.unified(qualities)
    }

    var body: some View {
        Group {
            // Keep the trigger separate from the scrubber gesture.
            if !title.isEmpty { qualityMenu }
        }
        .task(id: "\(player.currentTrack?.id ?? 0):\(account.offlineScope):\(player.currentUnblockSourceID?.rawValue ?? "")") {
            await loadQualities()
        }
    }

    private var qualityMenu: some View {
        Menu {
            qualityOptions
        } label: {
            HStack(spacing: 4) {
                if player.isSwitchingAudioQuality {
                    ProgressView().controlSize(.mini).tint(.white)
                } else if let badgeQuality,
                          [AudioQuality.lossless, .hires, .jyeffect, .sky, .jymaster].contains(badgeQuality) {
                    QualityWaveMark()
                        .stroke(style: StrokeStyle(lineWidth: 0.85, lineCap: .round, lineJoin: .round))
                        .frame(width: 15, height: 11)
                }
                Text(title)
                    .lineLimit(1)
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.70))
            .padding(.horizontal, 7)
            .frame(height: 21)
            .overlay {
                Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 0.75)
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, minHeight: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(title.isEmpty || player.currentTrack == nil || player.isSwitchingAudioQuality)
        .accessibilityLabel("当前音质")
        .accessibilityValue(title)
        .accessibilityHint("选择当前歌曲音质或总是最高")
        .accessibilityIdentifier("nowPlayingAudioQuality")
        .menuOrder(.fixed)
    }

    @ViewBuilder
    private var qualityOptions: some View {
        ForEach(options) { option in
            Toggle(option.title, isOn: Binding(
                get: { !settings.alwaysHighestAudioQuality && settings.audioQuality == option.quality },
                set: { selected in
                    guard selected else { return }
                    Task { await player.switchAudioQuality(to: option.quality, alwaysHighest: false) }
                }
            ))
        }
        if loading { Text("正在获取音质…") }
        if failed && !playsExternalSource {
            Button("重新获取音质列表") { Task { await loadQualities() } }
        } else if !loading && options.isEmpty {
            Text("当前音源暂无可切换音质")
        }
        Toggle("总是最高", isOn: Binding(
            get: { settings.alwaysHighestAudioQuality },
            set: { selected in
                Task { await player.switchAudioQuality(to: selected ? nil : settings.audioQuality, alwaysHighest: selected) }
            }
        ))
    }

    @MainActor
    private func loadQualities() async {
        guard let track = player.currentTrack else { qualities = []; externalQualities = []; return }
        let id = track.id
        if let source = player.currentUnblockSourceID {
            externalQualities = []
            loading = true
            failed = false
            let result = await UnblockResolver.qualityOptions(for: track, source: source)
            guard !Task.isCancelled, player.currentTrack?.id == id,
                  player.currentUnblockSourceID == source else { return }
            externalQualities = result
            loading = false
            return
        }
        let scope = account.offlineScope
        qualities = []
        loading = true
        failed = false
        do {
            let result = try await NeteaseAPI.songAudioQualityOptions(id: id)
            guard !Task.isCancelled, player.currentTrack?.id == id, account.offlineScope == scope else { return }
            qualities = result
            loading = false
        } catch {
            guard !Task.isCancelled, player.currentTrack?.id == id, account.offlineScope == scope else { return }
            loading = false
            failed = true
        }
    }
}
/// Three flowing strokes identify lossless/high-resolution audio without a
/// disclosure arrow. The mark remains crisp at the compact badge size.
private struct QualityWaveMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width * 0.72
        for wave in 0..<3 {
            let offset = CGFloat(wave) * rect.width * 0.14
            for step in 0...32 {
                let t = CGFloat(step) / 32
                let point = CGPoint(
                    x: rect.minX + offset + width * t,
                    y: rect.midY - sin(t * .pi * 2) * rect.height * 0.38
                )
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
        return path
    }
}
