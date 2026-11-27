import CoreText
import SwiftUI

/// Cached strips of the original Core Text layout preserve shaping, wrapping,
/// emoji and ruby. Only compositing changes at playback cadence; no retypesetting.
@MainActor
struct KaraokeGlyphRenderer {
    struct Tile {
        let image: CGImage
        let rect: CGRect
        let timings: [LyricTimingTextAttribute]
    }
    private var tiles: [Tile] = []
    private var cachedBounds: CGRect = .null
    private var attributed: NSAttributedString?
    private var timing: [LyricTimingTextAttribute] = []
    private var ranges: [NSRange] = []
    private var size: CGFloat = 0

    mutating func update(line: LyricLine, words: [LyricWord], segments: [RubySegment],
                         style: RubyAttributedString.Style) {
        attributed = RubyAttributedString.make(segments, style: style)
        size = style.size
        cachedBounds = .null
        tiles = []
        let joined = words.map(\.text).joined()
        let source = TimedLyricTextBuilder.attributes(from: words.map {
            LyricSyllable(text: $0.text, startTime: $0.start, endTime: $0.end)
        })
        let leading = joined.count - joined.drop(while: \.isWhitespace).count
        if joined == line.text {
            timing = source
        } else if joined.trimmingCharacters(in: .whitespacesAndNewlines) == line.text {
            timing = Array(source.dropFirst(leading).prefix(line.text.count))
        } else {
            timing = [] // Unmatched source must never illuminate unrelated characters.
        }
        ranges = []
        var location = 0
        for segment in segments {
            // Keep a ruby annotation and its base together to avoid tearing readings.
            let pieces = segment.ruby == nil ? segment.text.map(String.init) : [segment.text]
            for piece in pieces {
                let length = (piece as NSString).length
                ranges.append(NSRange(location: location, length: length))
                location += length
            }
        }
    }

    mutating func draw(in bounds: CGRect, context: CGContext, at time: TimeInterval) {
        guard let attributed, bounds.width > 0, bounds.height > 0 else { return }
        if cachedBounds != bounds {
            cachedBounds = bounds
            tiles = makeTiles(attributed, bounds: bounds)
        }
        guard !tiles.isEmpty else {
            RubyAttributedString.draw(attributed, in: bounds, context: context)
            return
        }
        let reduced = Platform.isReduceMotionEnabled
        for tile in tiles {
            let states = tile.timings.map { KaraokeGlyphVisualState.state(timing: $0, at: time) }
            let progress = states.isEmpty ? 1 : states.map(\.reveal).reduce(0, +) / Double(states.count)
            let lift = reduced ? 0 : (states.map(\.lift).max() ?? 0)
            let emphasis = reduced ? 0 : (states.map(\.emphasis).max() ?? 0)
            let glow = reduced ? 0 : (states.map(\.glow).max() ?? 0)
            context.saveGState()
            let scale = 1 + CGFloat(emphasis) * 0.075
            context.translateBy(x: tile.rect.midX, y: tile.rect.midY + CGFloat(lift) * size * 0.065)
            context.scaleBy(x: scale, y: scale)
            let rect = CGRect(x: -tile.rect.width / 2, y: -tile.rect.height / 2,
                              width: tile.rect.width, height: tile.rect.height)
            context.setAlpha(0.28)
            context.draw(tile.image, in: rect)
            if progress > 0 {
                context.setAlpha(1)
                // Shadow is applied to the revealed layer, so unsung ink cannot glow.
                context.setShadow(offset: .zero, blur: size * 0.24,
                                  color: PlatformColor.white.withAlphaComponent(glow * 0.65).cgColor)
                context.beginTransparencyLayer(auxiliaryInfo: nil)
                context.draw(tile.image, in: rect)
                if progress < 1 {
                    context.setBlendMode(.destinationIn)
                    let feather = min(rect.width * 0.45, size * 0.22)
                    let front = rect.minX - feather + (rect.width + 2 * feather) * progress
                    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(),
                                              colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)] as CFArray,
                                              locations: [0, 1])!
                    context.drawLinearGradient(gradient,
                        start: CGPoint(x: front - feather, y: 0), end: CGPoint(x: front + feather, y: 0),
                        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                }
                context.endTransparencyLayer()
            }
            context.restoreGState()
        }
    }

    private func makeTiles(_ string: NSAttributedString, bounds: CGRect) -> [Tile] {
        let scale: CGFloat = 2
        let fitted = RubyAttributedString.fittedSize(string, width: bounds.width)
        let height = max(bounds.height, ceil(fitted.height))
        let width = bounds.width
        guard width.isFinite, height.isFinite, width < 8192, height < 16384,
              let bitmap = CGContext(data: nil, width: Int(ceil(width * scale)), height: Int(ceil(height * scale)),
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        bitmap.scaleBy(x: scale, y: scale)
        bitmap.textMatrix = .identity
        let framesetter = CTFramesetterCreateWithAttributedString(string)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0),
            CGPath(rect: CGRect(x: 0, y: 0, width: width, height: height), transform: nil), nil)
        CTFrameDraw(frame, bitmap)
        guard let image = bitmap.makeImage() else { return [] }
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRangeMake(0, 0), &origins)
        var characterRanges: [NSRange] = []
        var offset = 0
        for character in string.string {
            let length = String(character).utf16.count
            characterRanges.append(NSRange(location: offset, length: length))
            offset += length
        }
        var result: [Tile] = []
        var top = height
        for (index, line) in lines.enumerated() {
            let origin = origins[index]
            var descent: CGFloat = 0
            CTLineGetTypographicBounds(line, nil, &descent, nil)
            let bottom = index == lines.count - 1 ? 0 : max(0, origin.y - descent - 1)
            let lineRange = CTLineGetStringRange(line)
            let nsLine = NSRange(location: lineRange.location, length: lineRange.length)
            for range in ranges {
                let intersection = NSIntersectionRange(range, nsLine)
                guard intersection.length > 0 else { continue }
                let first = CTLineGetOffsetForStringIndex(line, intersection.location, nil) + origin.x
                let last = CTLineGetOffsetForStringIndex(line, NSMaxRange(intersection), nil) + origin.x
                let left = max(0, floor(min(first, last) * scale))
                let right = min(CGFloat(image.width), ceil(max(first, last) * scale))
                let crop = CGRect(x: left, y: floor((height - top) * scale),
                                  width: right - left, height: ceil((top - bottom) * scale))
                guard crop.width > 0, crop.height > 0, let piece = image.cropping(to: crop) else { continue }
                let indices = characterRanges.indices.filter {
                    NSIntersectionRange(characterRanges[$0], intersection).length > 0
                }
                let times = indices.compactMap { $0 < timing.count ? timing[$0] : nil }
                result.append(Tile(image: piece,
                    rect: CGRect(x: bounds.minX + crop.minX / scale, y: bounds.maxY - crop.maxY / scale,
                                 width: crop.width / scale, height: crop.height / scale), timings: times))
            }
            top = bottom
        }
        return result
    }
}

/// Timing is absolute: pause and seek never leave an independent animation running.
enum KaraokeGlyphVisualState {
    struct State {
        let reveal: Double
        let lift: Double
        let emphasis: Double
        let glow: Double
    }

    static func state(timing: LyricTimingTextAttribute, at time: TimeInterval) -> State {
        guard !timing.isWhitespace else { return State(reveal: time >= timing.startTime ? 1 : 0, lift: 0, emphasis: 0, glow: 0) }
        let reveal = LyricHighlightRevealProgress.progress(playbackTime: time, timing: timing,
            detectionMode: .character, durationThreshold: 0.95)
        let progress = min(1, max(0, (time - timing.startTime) / max(0.001, timing.endTime - timing.startTime + 0.32)))
        let lift = progress * progress * (3 - 2 * progress)
        let emphasis = LyricLongToneEmphasis.state(playbackTime: time, timing: timing,
            detectionMode: .character, durationThreshold: 0.95)
        let attack = min(1, max(0, (time - timing.startTime) / 0.12))
        let tail = min(1, max(0, 1 - (time - timing.endTime) / 0.55))
        return State(reveal: reveal, lift: lift,
                     emphasis: emphasis.envelope * emphasis.expansionAmount,
                     glow: max(emphasis.envelope * emphasis.glowAmount, attack * tail * 0.48))
    }
}
