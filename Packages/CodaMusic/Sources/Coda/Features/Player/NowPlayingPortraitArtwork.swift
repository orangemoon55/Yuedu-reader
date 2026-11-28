// SPDX-License-Identifier: GPL-3.0-only
// Adapted from youshen2/MeloX NowPlayingPortraitArtwork.swift at
// 09713edb847a0f0a3515a34f779cc630d4fe5985. See ThirdPartyNotices/MeloX.md.
import SwiftUI

/// Pure policy shared with the offline/host tests. Require an intentional
/// horizontal trip; a vertical or diagonal scroll never changes lyric pages.
enum NowPlayingPortraitLyricsSwipe {
    static let minimumTravel: CGFloat = 56
    static let horizontalDominance: CGFloat = 1.8

    static func isHorizontal(_ translation: CGSize) -> Bool {
        translation.width.isFinite && translation.height.isFinite
            && abs(translation.width) > abs(translation.height) * horizontalDominance
    }

    static func targetVisibility(translation: CGSize, expanded: Bool) -> Bool? {
        guard isHorizontal(translation), abs(translation.width) >= minimumTravel else { return nil }
        if !expanded && translation.width > 0 { return true }
        if expanded && translation.width < 0 { return false }
        return nil
    }
}

enum NowPlayingPortraitLyricWindow {
    static func indices(count: Int, focus: Int?, expanded: Bool) -> Range<Int> {
        guard count > 0 else { return 0..<0 }
        if expanded { return 0..<count }
        let focus = min(count - 1, max(0, focus ?? 0))
        let start = max(0, min(focus - 1, count - min(4, count)))
        return start..<min(count, start + 4)
    }
}

#if os(iOS)
import UIKit
/// Independently implemented, steady circular artwork for the mist poster.
/// The compact lyric header keeps its rounded-square shape. No fabricated
/// rotation or playback-driven bounce is used; pausing never hides the cover.
struct NowPlayingPortraitArtwork: View {
    let image: PlatformImage?
    let isArtworkPage: Bool
    let isPlaying: Bool

    var body: some View {
        ZStack {
            Color(white: 0.15)
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: isArtworkPage ? 48 : 24, weight: .light))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: isArtworkPage ? 1000 : 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: isArtworkPage ? 1000 : 12, style: .continuous)
                .strokeBorder(.white.opacity(isArtworkPage ? 0.14 : 0), lineWidth: 1)
        }
        .shadow(color: .black.opacity(isArtworkPage ? 0.24 : 0),
                radius: isArtworkPage ? 24 : 0, y: isArtworkPage ? 12 : 0)
    }
}

struct PortraitLyricsEntranceID: Equatable {
    let expanded: Bool
    let trackID: Int?
    let prepared: Bool
}

/// Read-only text: no row buttons, tap recognizers, seek calls or player clock.
/// Full lyrics focus once on entry, then let the user browse without fighting
/// playback-follow. Cursor updates only change emphasis while browsing.
struct NowPlayingPortraitLyrics: View {
    let lyrics: ParsedLyrics?
    @ObservedObject var cursor: LyricsCursor
    let expanded: Bool
    let loadFailed: Bool
    @ScaledMetric(relativeTo: .title) private var lineSize: CGFloat = 29
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { viewport in
            if let lyrics, !lyrics.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: expanded) {
                        VStack(spacing: 26) {
                            ForEach(Array(NowPlayingPortraitLyricWindow.indices(
                                count: lyrics.lines.count, focus: cursor.activeIndex, expanded: expanded)), id: \.self) { index in
                                lyricText(lyrics.lines[index], index: index)
                                    .id(lyrics.lines[index].id)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)
                        .padding(.vertical, expanded ? max(24, viewport.size.height * 0.32) : 24)
                        .frame(minHeight: max(0, viewport.size.height))
                    }
                    .task(id: expanded) {
                        guard expanded, !lyrics.lines.isEmpty else { return }
                        let index = min(lyrics.lines.count - 1, max(0, cursor.activeIndex ?? 0))
                        proxy.scrollTo(lyrics.lines[index].id, anchor: .center)
                    }
                    .accessibilityIdentifier(expanded ? "portraitFullLyricsReadOnly" : "portraitLyricsPreview")
                }
            } else {
                VStack(spacing: 12) {
                    if lyrics == nil && !loadFailed {
                        ProgressView().tint(.white)
                    }
                    Text(lyrics?.isInstrumental == true ? "纯音乐，请欣赏"
                         : loadFailed ? "歌词加载失败" : lyrics == nil ? "歌词加载中…" : "暂无歌词")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .contentShape(Rectangle())
        .clipped()
        .accessibilityElement(children: .contain)
    }

    private func lyricText(_ line: LyricLine, index: Int) -> some View {
        let active = cursor.activeIndices.contains(index)
        return VStack(spacing: 8) {
            Text(line.text)
                .font(.system(size: lineSize, weight: .semibold, design: .rounded))
                .foregroundStyle(active ? Color(red: 0.99, green: 0.76, blue: 0.43)
                                 : .white.opacity(contrast == .increased ? 0.78 : 0.40))
            if let translation = line.translation, !translation.isEmpty {
                Text(translation)
                    .font(.body)
                    .foregroundStyle(.white.opacity(active ? 0.85 : 0.50))
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityValue(active ? "当前歌词" : "")
        .accessibilityIdentifier("portraitReadOnlyLyric-\(index)")
    }
}

/// Passive native observation follows the existing controls observer pattern.
/// The window hosts the recognizer, but only touches STARTING inside this
/// bounded lyric viewport are eligible. Controls/header are never observed.
struct PortraitLyricsSwipeObserver: UIViewRepresentable {
    let expanded: Bool
    let onChange: (Bool) -> Void

    final class ObserverView: UIView, UIGestureRecognizerDelegate {
        var expanded = false
        var onChange: ((Bool) -> Void)?
        private weak var observedWindow: UIWindow?
        private lazy var pan: UIPanGestureRecognizer = {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
            pan.maximumNumberOfTouches = 1
            pan.cancelsTouchesInView = false
            pan.delaysTouchesBegan = false
            pan.delaysTouchesEnded = false
            pan.delegate = self
            return pan
        }()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            detach()
            if let window {
                window.addGestureRecognizer(pan)
                observedWindow = window
            }
        }

        func detach() {
            observedWindow?.removeGestureRecognizer(pan)
            observedWindow = nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard !isHidden, window != nil, bounds.width > 0, bounds.height > 0 else { return false }
            return bounds.contains(touch.location(in: self))
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            let translation = pan.translation(in: self)
            let velocity = pan.velocity(in: self)
            // Reject vertical intent before recognition, not merely at release.
            guard NowPlayingPortraitLyricsSwipe.isHorizontal(CGSize(width: translation.x, height: translation.y)),
                  NowPlayingPortraitLyricsSwipe.isHorizontal(CGSize(width: velocity.x, height: velocity.y)) else { return false }
            return expanded ? translation.x < 0 : translation.x > 0
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Native scrolling and the parent downward dismissal retain ownership.
            true
        }

        @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            let translation = recognizer.translation(in: self)
            if let target = NowPlayingPortraitLyricsSwipe.targetVisibility(
                translation: CGSize(width: translation.x, height: translation.y), expanded: expanded) {
                onChange?(target)
            }
        }
    }

    func makeUIView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        view.expanded = expanded
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: ObserverView, context: Context) {
        view.expanded = expanded
        view.onChange = onChange
    }

    static func dismantleUIView(_ view: ObserverView, coordinator: ()) {
        view.onChange = nil
        view.detach()
    }
}
#endif
