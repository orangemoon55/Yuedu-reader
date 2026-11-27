import CoreText
import QuartzCore
import SwiftUI

/// Draws cached Core Text glyphs at display cadence. Reveal, glow, lift and
/// long-note emphasis never change the SwiftUI row's geometry.
struct KaraokeLyricLine: PlatformViewRepresentable {
    let line: LyricLine
    let words: [LyricWord]
    let size: CGFloat
    let weight: Font.Weight
    var color: Color = .white
    var alignment: NSTextAlignment = .left
    var rounded: Bool = false
    /// The wipe only advances while this reads true; otherwise the line stays
    /// frozen exactly where it was.
    let playing: Bool

    #if os(macOS)
    func makeNSView(context: Context) -> KaraokeLineView {
        let view = KaraokeLineView()
        view.update(line: line, words: words, size: size, weight: weight,
                    color: color, alignment: alignment, rounded: rounded,
                    playing: playing)
        return view
    }

    func updateNSView(_ view: KaraokeLineView, context: Context) {
        view.update(line: line, words: words, size: size, weight: weight,
                    color: color, alignment: alignment, rounded: rounded,
                    playing: playing)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: KaraokeLineView, context: Context) -> CGSize? {
        KaraokeLineView.fittedSize(line: line, size: size, weight: weight,
                                   alignment: alignment, rounded: rounded,
                                   width: proposal.width)
    }
    #else
    func makeUIView(context: Context) -> KaraokeLineView {
        let view = KaraokeLineView()
        view.update(line: line, words: words, size: size, weight: weight,
                    color: color, alignment: alignment, rounded: rounded,
                    playing: playing)
        return view
    }

    func updateUIView(_ view: KaraokeLineView, context: Context) {
        view.update(line: line, words: words, size: size, weight: weight,
                    color: color, alignment: alignment, rounded: rounded,
                    playing: playing)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: KaraokeLineView, context: Context) -> CGSize? {
        KaraokeLineView.fittedSize(line: line, size: size, weight: weight,
                                   alignment: alignment, rounded: rounded,
                                   width: proposal.width)
    }
    #endif
}

/// Shared cached typography and animation invalidation for both native hosts.
@MainActor
private struct KaraokeLineContent {
    private var line: LyricLine?
    private var words: [LyricWord] = []
    private var style: RubyAttributedString.Style?
    private var lastQuantizedAlphas: [Int] = []
    private var renderer = KaraokeGlyphRenderer()
    private var timing: [LyricTimingTextAttribute] = []
    private var inputs: Inputs?

    /// Everything that shapes the cached typesetting. SwiftUI calls
    /// `updateUIView` on every parent invalidation; rebuilding the Core Text
    /// layout and glyph tiles there is what made line changes stutter.
    private struct Inputs: Equatable {
        let line: LyricLine
        let words: [LyricWord]
        let size: CGFloat
        let weight: Font.Weight
        let color: PlatformColor
        let alignment: NSTextAlignment
        let rounded: Bool
        let furigana: Bool
    }

    /// Returns false when nothing about the typesetting changed.
    @discardableResult
    mutating func update(line: LyricLine, words: [LyricWord], size: CGFloat,
                         weight: Font.Weight, color: PlatformColor,
                         alignment: NSTextAlignment, rounded: Bool) -> Bool {
        let next = Inputs(line: line, words: words, size: size, weight: weight, color: color,
                          alignment: alignment, rounded: rounded,
                          furigana: SettingsManager.shared.lyricsAnnotation == .furigana)
        guard next != inputs else { return false }
        inputs = next
        self.line = line
        self.words = words
        lastQuantizedAlphas = []
        style = RubyAttributedString.Style(
            size: size,
            weight: weight.platform,
            color: color,
            rubyColor: color.withAlphaComponent(color.cgColor.alpha * 0.72),
            rubyScale: 0.5,
            alignment: alignment,
            rounded: rounded
        )
        if let style {
            renderer.update(line: line, words: words, segments: Self.segments(for: line), style: style)
        }
        timing = TimedLyricTextBuilder.attributes(from: words.map {
            LyricSyllable(text: $0.text, startTime: $0.start, endTime: $0.end)
        })
        return true
    }

    mutating func draw(in bounds: CGRect, context: CGContext, at time: TimeInterval) {
        renderer.draw(in: bounds, context: context, at: time)
    }

    /// Skip unchanged frames, while retaining lift continuation and glow tails
    /// after the last character finishes revealing.
    mutating func wipeHasMoved(at time: TimeInterval) -> Bool {
        guard line != nil, !words.isEmpty else { return false }
        let quantized = timing.flatMap { timing -> [Int] in
            let state = KaraokeGlyphVisualState.state(timing: timing, at: time)
            return [state.reveal, state.lift, state.emphasis, state.glow]
                .map { Int(($0 * 128).rounded()) }
        }
        guard quantized != lastQuantizedAlphas else { return false }
        lastQuantizedAlphas = quantized
        return true
    }

    /// Measures the line without building glyph tiles. Results are cached:
    /// SwiftUI asks for the size several times per layout pass, and the lazy
    /// stack measures again whenever a row re-enters the viewport.
    static func fittedSize(line: LyricLine, size: CGFloat, weight: Font.Weight,
                           alignment: NSTextAlignment, rounded: Bool, width: CGFloat?) -> CGSize {
        let proposed = width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let segments = segments(for: line)
        let key = SizeKey(segments: segments, size: size, weight: weight, alignment: alignment,
                          rounded: rounded, width: proposed)
        if let cached = sizeCache[key] { return cached }
        let style = RubyAttributedString.Style(
            size: size, weight: weight.platform, color: .white, rubyColor: .white,
            rubyScale: 0.5, alignment: alignment, rounded: rounded
        )
        let attributed = RubyAttributedString.make(segments, style: style)
        let result: CGSize
        if let proposed {
            let fitted = RubyAttributedString.fittedSize(attributed, width: proposed)
            result = CGSize(width: proposed, height: ceil(fitted.height))
        } else {
            let fitted = RubyAttributedString.fittedSize(attributed, width: .greatestFiniteMagnitude)
            result = CGSize(width: ceil(fitted.width), height: ceil(fitted.height))
        }
        if sizeCache.count >= 256 { sizeCache.removeAll(keepingCapacity: true) }
        sizeCache[key] = result
        return result
    }

    private struct SizeKey: Hashable {
        let segments: [RubySegment]
        let size: CGFloat
        let weight: Font.Weight
        let alignment: NSTextAlignment
        let rounded: Bool
        let width: CGFloat?
    }

    private static var sizeCache: [SizeKey: CGSize] = [:]

    /// The line's runs — the furigana segments when the reader has chosen
    /// them, else the plain text; the wipe rides either.
    private static func segments(for line: LyricLine) -> [RubySegment] {
        if SettingsManager.shared.lyricsAnnotation == .furigana, let furigana = line.furigana {
            return furigana
        }
        return [RubySegment(line.text)]
    }
}

#if os(macOS)
/// The host for a karaoke line: draws the line, and runs a display link that
/// redraws it at up to 30 fps while the wipe is advancing.
final class KaraokeLineView: NSView {
    private var content = KaraokeLineContent()
    private var playing = false
    private var displayLink: CADisplayLink?
    private var lastDraw: CFTimeInterval = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(line: LyricLine, words: [LyricWord], size: CGFloat,
                weight: Font.Weight, color: Color, alignment: NSTextAlignment,
                rounded: Bool, playing: Bool) {
        let typesettingChanged = content.update(
            line: line, words: words, size: size, weight: weight,
            color: PlatformColor(color), alignment: alignment, rounded: rounded)
        let playingChanged = playing != self.playing
        if playingChanged {
            self.playing = playing
            if playing {
                startDisplayLink()
            } else {
                stopDisplayLink()
            }
        }
        // A running display link already redraws whenever the wipe moves.
        if typesettingChanged || playingChanged || !playing { needsDisplay = true }
    }

    static func fittedSize(line: LyricLine, size: CGFloat, weight: Font.Weight,
                           alignment: NSTextAlignment, rounded: Bool,
                           width: CGFloat?) -> CGSize? {
        let fitted = KaraokeLineContent.fittedSize(line: line, size: size, weight: weight,
                                                   alignment: alignment, rounded: rounded,
                                                   width: width.map { max(1, $0 - 16) })
        return CGSize(width: fitted.width + 16, height: fitted.height + 16)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopDisplayLink()
        } else if playing {
            startDisplayLink()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        content.draw(in: bounds.insetBy(dx: 8, dy: 8), context: context, at: PlayerService.shared.lyricsCursor.playbackTime)
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        lastDraw = 0
        let link = displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        // The drawing surface ticks independently of SwiftUI layout.
        guard now - lastDraw >= 1.0 / 30 else { return }
        guard content.wipeHasMoved(at: PlayerService.shared.lyricsCursor.playbackTime) else { return }
        lastDraw = now
        needsDisplay = true
    }
}
#else
/// The host for a karaoke line: draws the line, and runs a display link that
/// redraws it at up to 30 fps while the wipe is advancing.
@MainActor
private final class KaraokeLineLinkTarget: NSObject {
    weak var view: KaraokeLineView?
    @objc func step(_ link: CADisplayLink) { view?.step(link) }
}

final class KaraokeLineView: UIView {
    private var content = KaraokeLineContent()
    private var playing = false
    private var displayLink: CADisplayLink?
    private var lastDraw: CFTimeInterval = 0
    private let linkTarget = KaraokeLineLinkTarget()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentMode = .redraw
        NotificationCenter.default.addObserver(self, selector: #selector(suspendRendering),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resumeRendering),
            name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        NotificationCenter.default.removeObserver(self)
        displayLink?.invalidate()
    }

    @objc private func suspendRendering() { stopDisplayLink() }

    @objc private func resumeRendering() {
        // A display link may have missed an entire line while suspended.
        // Redraw even when playback is now paused or the wipe is unchanged.
        if playing { startDisplayLink() }
        setNeedsDisplay()
    }

    func update(line: LyricLine, words: [LyricWord], size: CGFloat,
                weight: Font.Weight, color: Color, alignment: NSTextAlignment,
                rounded: Bool, playing: Bool) {
        let typesettingChanged = content.update(
            line: line, words: words, size: size, weight: weight,
            color: PlatformColor(color), alignment: alignment, rounded: rounded)
        let playingChanged = playing != self.playing
        if playingChanged {
            self.playing = playing
            if playing {
                startDisplayLink()
            } else {
                stopDisplayLink()
            }
        }
        // A running display link already redraws whenever the wipe moves.
        if typesettingChanged || playingChanged || !playing { setNeedsDisplay() }
    }

    static func fittedSize(line: LyricLine, size: CGFloat, weight: Font.Weight,
                           alignment: NSTextAlignment, rounded: Bool,
                           width: CGFloat?) -> CGSize? {
        let fitted = KaraokeLineContent.fittedSize(line: line, size: size, weight: weight,
                                                   alignment: alignment, rounded: rounded,
                                                   width: width.map { max(1, $0 - 16) })
        return CGSize(width: fitted.width + 16, height: fitted.height + 16)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopDisplayLink()
        } else if playing {
            startDisplayLink()
        }
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.textMatrix = .identity
        // Core Text draws bottom-up; UIKit hands over a top-down context.
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        content.draw(in: bounds.insetBy(dx: 8, dy: 8), context: context, at: PlayerService.shared.lyricsCursor.playbackTime)
        context.restoreGState()
    }

    private func startDisplayLink() {
        guard displayLink == nil, window != nil,
              UIApplication.shared.applicationState != .background else { return }
        lastDraw = 0
        linkTarget.view = self
        let link = CADisplayLink(target: linkTarget, selector: #selector(KaraokeLineLinkTarget.step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    fileprivate func step(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        guard now - lastDraw >= 1.0 / 30 else { return }
        guard content.wipeHasMoved(at: PlayerService.shared.lyricsCursor.playbackTime) else { return }
        lastDraw = now
        setNeedsDisplay()
    }
}
#endif