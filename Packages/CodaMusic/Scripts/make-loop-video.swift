// 把一段录屏剪成可循环播放的 MP4，用于落地页的动态截图。
//
// 用法：
//   swift Scripts/make-loop-video.swift <输入.mov> <输出.mp4> <输出宽度> <首尾淡入淡出秒数> <开头裁掉秒数> [封面.jpg]
// 例如：
//   swift Scripts/make-loop-video.swift docs/assets/recordings/mac/player-raw.mov \
//     site/assets/video/mac-player.mp4 1440 1.0 0.3 site/assets/video/mac-player.jpg
//
// 做法：开头淡入、结尾淡出到黑色，循环点像屏幕眨一下；不把首尾画面叠在一起，
// 因为播放中的歌词、进度和背景叠加后会出现重影。窗口四角录到的桌面像素会被涂黑。
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 6 else {
    print("用法：swift make-loop-video.swift <输入> <输出.mp4> <宽度> <淡入淡出秒数> <裁掉秒数> [封面.jpg]")
    exit(1)
}
let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])
let outW = Int(args[3])!
let fade = Double(args[4])!
let trim = Double(args[5])!
let posterPath = args.count > 6 ? args[6] : nil
let fps = 30.0
let cornerRadius = 10.0  // 输出像素；对应 macOS 窗口圆角

let asset = AVURLAsset(url: input)
let duration = asset.duration.seconds
let track = asset.tracks(withMediaType: .video)[0]
let natural = track.naturalSize.applying(track.preferredTransform)
let srcW = abs(natural.width), srcH = abs(natural.height)
let outH = Int((Double(outW) * srcH / srcW).rounded()) / 2 * 2

let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
generator.maximumSize = CGSize(width: outW, height: outH)

func image(at seconds: Double) -> CGImage {
    try! generator.copyCGImage(at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil)
}

let loopLength = duration - trim - 0.1
guard loopLength > 1 else { print("录屏太短"); exit(1) }
let frameCount = Int(loopLength * fps)
print(String(format: "源 %.0fx%.0f %.2fs → 输出 %dx%d，循环 %.2fs，%d 帧", srcW, srcH, duration, outW, outH, loopLength, frameCount))

try? FileManager.default.removeItem(at: output)
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: outW,
    AVVideoHeightKey: outH,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 3_000_000,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        AVVideoMaxKeyFrameIntervalKey: 60,
    ],
])
writerInput.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: outW,
    kCVPixelBufferHeightKey as String: outH,
])
writer.add(writerInput)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

let rect = CGRect(x: 0, y: 0, width: outW, height: outH)
let corners = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

func render(into buffer: CVPixelBuffer, t: Double) -> CGImage? {
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: outW, height: outH,
                        bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fill(rect)
    ctx.addPath(corners)
    ctx.clip()
    // 首尾淡入淡出黑场；中间始终只画一帧真实画面
    let alpha = max(0, min(1, t / fade, (loopLength - t) / fade))
    ctx.setAlpha(CGFloat(alpha))
    ctx.draw(image(at: trim + t), in: rect)
    return ctx.makeImage()
}

for i in 0..<frameCount {
    let t = Double(i) / fps
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
    let frameImage = render(into: buffer!, t: t)
    if i == Int(fps * 5), let posterPath, let frameImage {  // 封面取第 5 秒，避开开头的淡入
        let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: posterPath) as CFURL,
                                                   UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, frameImage, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }
    while !writerInput.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.01) }
    adaptor.append(buffer!, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
}

writerInput.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
if writer.status != .completed { print("写入失败：\(String(describing: writer.error))"); exit(1) }
print("完成：\(output.path)")
