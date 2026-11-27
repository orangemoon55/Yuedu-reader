#if os(iOS)
import AVFAudio
import MediaPlayer
import SwiftUI

/// Native volume interaction with the player's existing compact artwork.
struct IOSSystemVolumeSlider: View {
    var trackHeight: CGFloat = NowPlayingSliderStyle.trackHeight
    var showsLevelIcon = false
    @StateObject private var volume = SystemVolume()

    var body: some View {
        HStack(spacing: Theme.Spacing.control) {
            SystemVolumeBridge(trackHeight: trackHeight)
                .frame(maxWidth: .infinity)
                .layoutPriority(1)
            if showsLevelIcon {
                PlayerVolumeIcon(volume: volume.fraction)
            }
        }
    }

    /// Observation only drives the adjacent icon. MPVolumeView owns the slider's
    /// value, accessibility adjustments and complete touch sequence.
    private final class SystemVolume: ObservableObject {
        @Published private(set) var fraction = Double(AVAudioSession.sharedInstance().outputVolume)
        private var observation: NSKeyValueObservation?

        init() {
            observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.initial, .new]) {
                [weak self] _, _ in
                DispatchQueue.main.async { [weak self] in
                    self?.fraction = Double(AVAudioSession.sharedInstance().outputVolume)
                }
            }
        }
    }

    private struct SystemVolumeBridge: UIViewRepresentable {
        let trackHeight: CGFloat

        func makeUIView(context: Context) -> CompactVolumeView {
            CompactVolumeView(trackHeight: trackHeight)
        }

        func updateUIView(_ view: CompactVolumeView, context: Context) {
            view.applyStyle(trackHeight: trackHeight)
        }

        func sizeThatFits(_ proposal: ProposedViewSize, uiView: CompactVolumeView,
                         context: Context) -> CGSize? {
            CGSize(width: proposal.width ?? 200, height: proposal.height ?? 44)
        }
    }

    private final class CompactVolumeView: MPVolumeView {
        private var styledTrackHeight: CGFloat?

        init(trackHeight: CGFloat) {
            super.init(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
            backgroundColor = .clear
            showsRouteButton = false
            showsVolumeSlider = true
            applyStyle(trackHeight: trackHeight)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func volumeSliderRect(forBounds bounds: CGRect) -> CGRect { bounds }

        func applyStyle(trackHeight: CGFloat) {
            let height = max(1, trackHeight)
            guard styledTrackHeight != height else { return }
            styledTrackHeight = height
            let minimum = Self.trackImage(height: height, color: .white)
            let maximum = Self.trackImage(height: height,
                                          color: .white.withAlphaComponent(NowPlayingSliderStyle.trackOpacity))
            let thumb = Self.thumbImage(visible: true)
            let hiddenThumb = Self.thumbImage(visible: false)
            for state: UIControl.State in [.normal, .highlighted, .disabled] {
                setMinimumVolumeSliderImage(minimum, for: state)
                setMaximumVolumeSliderImage(maximum, for: state)
                setVolumeThumbImage(state == .highlighted ? thumb : hiddenThumb, for: state)
            }
            // Keep VoiceOver on the native adjustable control.
            subviews.compactMap { $0 as? UISlider }.first?.accessibilityLabel = "音量"
        }

        private static func trackImage(height: CGFloat, color: UIColor) -> UIImage {
            let size = CGSize(width: height * 2 + 1, height: height)
            return UIGraphicsImageRenderer(size: size).image { _ in
                color.setFill()
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: size),
                             cornerRadius: height / 2).fill()
            }.resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: height,
                                                        bottom: 0, right: height))
        }

        private static func thumbImage(visible: Bool) -> UIImage {
            let diameter = NowPlayingSliderStyle.draggingThumbDiameter
            let inset: CGFloat = 3
            let size = CGSize(width: diameter + inset * 2, height: diameter + inset * 2)
            return UIGraphicsImageRenderer(size: size).image { renderer in
                guard visible else { return }
                renderer.cgContext.setShadow(
                    offset: CGSize(width: 0, height: NowPlayingSliderStyle.thumbShadowOffset),
                    blur: NowPlayingSliderStyle.thumbShadowRadius,
                    color: UIColor.black.withAlphaComponent(NowPlayingSliderStyle.thumbShadowOpacity).cgColor)
                UIColor.white.setFill()
                UIBezierPath(ovalIn: CGRect(x: inset, y: inset, width: diameter, height: diameter)).fill()
            }
        }
    }
}
#endif
