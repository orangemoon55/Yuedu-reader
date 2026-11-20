import CoreGraphics
import Foundation
import ImageIO
import JavaScriptCore
import UIKit

@objc protocol LegadoBitmapPixelsExport: JSExport {
    func getWidth() -> Int
    func getHeight() -> Int
    func copyRect(_ source: JSValue, _ from: [Int], _ to: [Int]) -> Bool
    func pngBytes() -> [Int]
}

/// Unrotated, top-left-origin RGBA pixels, like Android BitmapFactory (no EXIF rotation).
/// Retained by its JS value, not a process-wide handle table; pages release their bitmaps.
@objc final class LegadoBitmapPixels: NSObject, LegadoBitmapPixelsExport {
    let width: Int
    let height: Int
    var pixels: [UInt8]
    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width; self.height = height; self.pixels = pixels
    }
    func getWidth() -> Int { width }
    func getHeight() -> Int { height }
    func copyRect(_ source: JSValue, _ from: [Int], _ to: [Int]) -> Bool {
        guard let source = source.toObject() as? LegadoBitmapPixels,
              from.count == 4, to.count == 4,
              from[0] >= 0, from[1] >= 0, from[2] <= source.width, from[3] <= source.height,
              to[0] >= 0, to[1] >= 0, to[2] <= width, to[3] <= height else { return false }
        // Android Canvas ignores empty rectangles (a very short image can have move == 0).
        if from[2] <= from[0] || from[3] <= from[1] || to[2] <= to[0] || to[3] <= to[1] { return true }
        // Paint() has filtering disabled; the source rule uses 1:1 rectangles, including
        // the remainder rows. Read a snapshot so a bitmap may also draw onto itself.
        let input = source.pixels
        for y in to[1]..<to[3] {
            let sy = from[1] + (y - to[1]) * (from[3] - from[1]) / (to[3] - to[1])
            for x in to[0]..<to[2] {
                let sx = from[0] + (x - to[0]) * (from[2] - from[0]) / (to[2] - to[0])
                let a = (sy * source.width + sx) * 4
                let b = (y * width + x) * 4
                for channel in 0..<4 { pixels[b + channel] = input[a + channel] }
            }
        }
        return true
    }
    func pngBytes() -> [Int] {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let data = UIImage(cgImage: image).pngData() else { return [] }
        return data.map(Int.init)
    }
}

@objc protocol LegadoBitmapFactoryExport: JSExport {
    func decode(_ bytes: JSValue, _ offset: Int, _ length: Int) -> LegadoBitmapPixels?
    func create(_ width: Int, _ height: Int) -> LegadoBitmapPixels?
}
@objc final class LegadoBitmapFactory: NSObject, LegadoBitmapFactoryExport {
    // Two RGBA bitmaps of at most 64 MB each, in addition to the bounded compressed bytes.
    private let maxPixels = 16_000_000
    func create(_ width: Int, _ height: Int) -> LegadoBitmapPixels? {
        guard width > 0, height > 0, width <= maxPixels / height else { return nil }
        return LegadoBitmapPixels(width: width, height: height, pixels: [UInt8](repeating: 0, count: width * height * 4))
    }
    func decode(_ bytes: JSValue, _ offset: Int, _ length: Int) -> LegadoBitmapPixels? {
        guard offset >= 0, length > 0, length <= 32 * 1024 * 1024,
              let count = bytes.forProperty("length")?.toDouble(), count.isFinite,
              Double(offset) + Double(length) <= count else { return nil }
        var data = Data(capacity: length)
        for i in offset..<(offset + length) {
            guard let number = bytes.atIndex(i), number.isNumber else { return nil }
            let value = number.toDouble()
            guard value.isFinite else { return nil }
            data.append(UInt8(truncatingIfNeeded: Int(value.truncatingRemainder(dividingBy: 256))))
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int,
              let target = create(w, h), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let success = target.pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return success ? target : nil
    }
}

enum LegadoBitmapRuntime {
    static func install(in context: JSContext) {
        context.setObject(LegadoBitmapFactory(), forKeyedSubscript: "__yueduBitmapNative" as NSString)
        context.evaluateScript(script)
    }
    private static let script = #"""
    (function(g) {
        var native = g.__yueduBitmapNative;
        function Bitmap(value) { this._pixels = value; }
        Bitmap.prototype.getWidth = function() { return this._pixels.getWidth(); };
        Bitmap.prototype.getHeight = function() { return this._pixels.getHeight(); };
        Bitmap.prototype.compress = function(format, quality, stream) {
            if (format !== 'PNG') throw new Error('Unsupported bitmap compression: ' + format);
            var bytes = this._pixels.pngBytes();
            if (!bytes.length) return false;
            stream.write(bytes); return true;
        };
        Bitmap.Config = { ARGB_8888: 'ARGB_8888' };
        Bitmap.CompressFormat = { PNG: 'PNG' };
        Bitmap.createBitmap = function(w,h,config) {
            if (config !== 'ARGB_8888') throw new Error('Unsupported bitmap config');
            var value = native.create(w,h);
            if (!value) throw new Error('Bitmap dimensions exceed pixel budget');
            return new Bitmap(value);
        };
        function Rect(l,t,r,b) { this.values = [l,t,r,b]; }
        function Paint() {}
        function Canvas(bitmap) { this.bitmap = bitmap; }
        Canvas.prototype.drawBitmap = function(source, from, to, paint) {
            if (!this.bitmap._pixels.copyRect(source._pixels, from.values, to.values)) {
                throw new Error('Invalid bitmap source/destination rectangle');
            }
        };
        g.__yueduBitmapGraphics = {
            Bitmap: Bitmap, Canvas: Canvas, Rect: Rect, Paint: Paint,
            BitmapFactory: { decodeByteArray: function(bytes,offset,length) {
                var value = native.decode(bytes,offset,length);
                return value ? new Bitmap(value) : null;
            }}
        };
    })(this);
    """#
}
