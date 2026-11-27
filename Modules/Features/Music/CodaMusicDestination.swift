import SwiftUI
@preconcurrency import CodaCore

/// Thin host chrome only: every music page, player, theme and animation is Coda's.
struct CodaMusicDestination: View {
    let isLibrary: Bool
    let onClose: () -> Void
    @State private var showsLegacySources = false

    var body: some View {
        IOSMainWindow(initialDestination: isLibrary ? .library : .home,
                      onDeclineDisclaimer: onClose)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Button(action: onClose) { Label("返回阅读", systemImage: "xmark") }
                        .accessibilityIdentifier("mediaHub.close")
                    Spacer()
                    Button { showsLegacySources = true } label: {
                        Label("JS 音乐源", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .accessibilityIdentifier("codaHost.legacySources")
                }
                .font(.subheadline)
                .padding(.horizontal).padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }
            .sheet(isPresented: $showsLegacySources) {
                NavigationStack {
                    MusicJSSourceView(isLibrary: isLibrary)
                        .navigationTitle("JS 音乐源")
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("关闭") { showsLegacySources = false }
                            }
                        }
                }
            }
    }
}

/// Installed once by the existing app delegate, not by a view appearance.
@MainActor
enum ReadccCodaAudioHost {
    static func install() {
        ReadccHostBridge.configureEmbeddedHost()
        ReadccHostBridge.audio.installReadccStop {
            TTSCoordinator.yieldSystemMediaToMusic() // Includes settings voice previews.
            NowPlayingHub.shared.yieldToCoda()
            AudioSessionActivator.finishPendingOperationsForTakeover()
        }
    }

    static func claimReadcc() { ReadccHostBridge.audio.claim(.readcc) }
    static var codaOwnsAudio: Bool { ReadccHostBridge.audio.owner == .coda }
}
