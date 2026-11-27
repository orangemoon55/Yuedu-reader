// SPDX-License-Identifier: GPL-3.0-only
// Adapted from youshen2/MeloX NowPlayingPortraitArtwork.swift at
// 09713edb847a0f0a3515a34f779cc630d4fe5985. See ThirdPartyNotices/MeloX.md.
import SwiftUI

#if os(iOS)
/// Portrait artwork backed by the already-loaded cover image.
struct NowPlayingPortraitArtwork: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let image: PlatformImage?
    let isArtworkPage: Bool
    let isPlaying: Bool

    @State private var bounceScale: CGFloat = 1

    var body: some View {
        ZStack {
            Rectangle().fill(.white.opacity(0.06))
                .overlay {
                    if image == nil {
                        Image(systemName: "music.note")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .scaleEffect(bounceScale)
        .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowOffset)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: isPlaying)
        .task(id: shouldBounce) { await animateBounce() }
        .onChange(of: reduceMotion) { reduced in
            if reduced { resetBounce() }
        }
    }

    private var shouldBounce: Bool { isArtworkPage && isPlaying && !reduceMotion }
    private var shadowOpacity: Double { isArtworkPage ? (isPlaying ? 0.34 : 0.18) : 0 }
    private var shadowRadius: CGFloat { isArtworkPage ? (isPlaying ? 26 : 14) : 0 }
    private var shadowOffset: CGFloat { isArtworkPage ? (isPlaying ? 15 : 8) : 0 }

    private func resetBounce() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { bounceScale = 1 }
    }

    private func animateBounce() async {
        resetBounce()
        guard shouldBounce else { return }
        await Task.yield()
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.17)) { bounceScale = 1.055 }
        do { try await Task.sleep(for: .milliseconds(170)) }
        catch { return }
        guard !Task.isCancelled else { return }
        if #available(iOS 17, *) {
            withAnimation(.spring(duration: 0.42, bounce: 0.24)) { bounceScale = 1 }
        } else {
            // iOS 16 has no duration/bounce spring API.
            withAnimation(.spring(response: 0.42, dampingFraction: 0.76)) { bounceScale = 1 }
        }
    }
}

struct PortraitArtworkFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 0, next.height > 0 { value = next }
    }
}

struct PortraitLyricsEntranceID: Equatable {
    let expanded: Bool
    let trackID: Int?
    let prepared: Bool
}
#endif
