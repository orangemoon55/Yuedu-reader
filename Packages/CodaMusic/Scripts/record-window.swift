// 只录某个应用的主窗口（被其他窗口挡住也能录到，不含鼠标指针），输出 .mov。
//
// 用法：
//   swift Scripts/record-window.swift <bundle id> <秒数> <输出.mov>
// 例如：
//   swift Scripts/record-window.swift wow.caicai.coda.dev 12 docs/assets/recordings/mac/player-raw.mov
//
// 需要“屏幕录制”权限；录完的文件交给 make-loop-video.swift 剪成循环片段。
import AppKit
import AVFoundation
import Foundation
import ScreenCaptureKit

// 命令行进程要先连上窗口服务，ScreenCaptureKit 才能工作
_ = NSApplication.shared

let args = CommandLine.arguments
guard args.count >= 4, let seconds = Double(args[2]) else {
    print("用法：swift record-window.swift <bundle id> <秒数> <输出.mov>")
    exit(1)
}
let bundleID = args[1]
let output = URL(fileURLWithPath: args[3])

final class Recorder: NSObject, SCStreamOutput {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    var started = false
    var frames = 0

    init(width: Int, height: Int) throws {
        try? FileManager.default.removeItem(at: output)
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        writer = try AVAssetWriter(outputURL: output, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 40_000_000],
        ])
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        writer.startWriting()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sample.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete,
              let pixels = CMSampleBufferGetImageBuffer(sample) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sample)
        if !started {
            writer.startSession(atSourceTime: time)
            started = true
        }
        if input.isReadyForMoreMediaData, adaptor.append(pixels, withPresentationTime: time) { frames += 1 }
    }
}

Task {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        guard let window = content.windows
            .filter({ $0.owningApplication?.bundleIdentifier == bundleID && $0.windowLayer == 0 })
            .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
            print("找不到 \(bundleID) 的窗口")
            exit(1)
        }
        let scale = 2.0
        let width = Int(window.frame.width * scale) / 2 * 2
        let height = Int(window.frame.height * scale) / 2 * 2
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 8
        let recorder = try Recorder(width: width, height: height)
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: config, delegate: nil)
        try stream.addStreamOutput(recorder, type: .screen, sampleHandlerQueue: DispatchQueue(label: "record"))
        print("开始录制「\(window.title ?? "")」\(width)x\(height)，\(seconds) 秒")
        try await stream.startCapture()
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        try await stream.stopCapture()
        recorder.input.markAsFinished()
        await recorder.writer.finishWriting()
        print("完成：\(recorder.frames) 帧 → \(output.path)")
    } catch {
        print("录制失败：\(error)")
        exit(1)
    }
    exit(0)
}
RunLoop.main.run()
