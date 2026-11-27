import CoreGraphics
import Foundation
import ImageIO
import MetalKit
import SwiftUI
import Testing
@testable import CodaCore

@MainActor
@Suite struct FluidBackgroundTests {
    @Test func decorativeNativeBackgroundNeverCapturesInput() {
        let background = FluidBackgroundNativeView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        for point in [CGPoint(x: 0, y: 0), CGPoint(x: 500, y: 350), CGPoint(x: 999, y: 699)] {
            #if os(iOS)
            #expect(!background.isUserInteractionEnabled)
            #expect(background.hitTest(point, with: nil) == nil)
            // Stay transparent even if a container re-enables UIView interaction.
            background.isUserInteractionEnabled = true
            #expect(!background.point(inside: point, with: nil))
            #expect(background.hitTest(point, with: nil) == nil)
            background.isUserInteractionEnabled = false
            #else
            #expect(background.hitTest(point) == nil)
            #endif
        }
    }

    @Test func rendererPreparationIsSharedAndOffMainThread() async {
        async let first = ArtworkFlowRenderer.prepared()
        async let second = ArtworkFlowRenderer.prepared()
        let (a, b) = await (first, second)
        #expect(a === b)
        #expect(!a.preparedOnMainThread)
    }

    @Test func drawableWaitCannotBlockTheMainThreadOrQueueStaleFrames() async {
        let producer = ArtworkFlowFrameProducer()
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let offMain = await withCheckedContinuation { continuation in
            producer.submit {
                continuation.resume(returning: !Thread.isMainThread)
                // Model nextDrawable waiting for the compositor during a slide.
                gate.wait()
            }
        }
        #expect(offMain)
        // The main actor reaches here even while the worker is still waiting.
        // Another frame must be dropped immediately, rather than accumulate.
        #expect(!producer.submit { })
    }

    @Test func repeatedArtworkRequestsReuseThePreparedTexture() async throws {
        let renderer = await ArtworkFlowRenderer.prepared()
        let cache = ArtworkFlowTextureCache()
        let context = try #require(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.8, green: 0.15, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let image = try #require(context.makeImage())
        async let first = cache.texture(for: image, key: "same-cover", renderer: renderer)
        async let second = cache.texture(for: image, key: "same-cover", renderer: renderer)
        let (a, b) = await (first, second)
        let texture = try #require(a)
        #expect(texture === b)
        let third = await cache.texture(for: image, key: "same-cover", renderer: renderer)
        #expect(texture === third)
    }

    @Test func silentMusicStillMovesWithoutInventingBeats() {
        var motion = FluidBackgroundMotion()
        for _ in 0..<90 { motion.advance(delta: 1.0 / 30, bass: 0, lowerMid: 0) }
        #expect(abs(motion.time - 3) < 0.001)
        #expect(motion.pulse == 0)
        #expect(motion.energy == 0)
    }

    @Test func bassOnsetExpandsThenReleases() {
        var motion = FluidBackgroundMotion()
        motion.advance(delta: 1.0 / 30, bass: 0.9, lowerMid: 0.1, bassOnset: 0.9)
        #expect(motion.pulse > 0.8)
        #expect(motion.energy > 0)
        for _ in 0..<60 { motion.advance(delta: 1.0 / 30, bass: 0, lowerMid: 0) }
        #expect(motion.pulse < 0.001)
        #expect(motion.energy < 0.001)
    }

    @Test func constantBassSettlesAndPausePreservesFlowPosition() {
        var motion = FluidBackgroundMotion()
        for _ in 0..<150 { motion.advance(delta: 1.0 / 30, bass: 0.7, lowerMid: 0.2) }
        #expect(motion.pulse < 0.001)
        let time = motion.time
        motion.silence()
        #expect(motion.pulse == 0)
        #expect(motion.energy == 0)
        #expect(motion.time == time)
    }

    @Test func melodicOnsetHasItsOwnSmallPulseAndSustainedNotesSettle() {
        var motion = FluidBackgroundMotion()
        motion.advance(delta: 1.0 / 30, bass: 0, lowerMid: 0, mid: 0.8, melodyOnset: 0.9)
        #expect(motion.melodyPulse > 0.8)
        #expect(motion.pulse == 0)
        for _ in 0..<150 {
            motion.advance(delta: 1.0 / 30, bass: 0, lowerMid: 0, mid: 0.8)
        }
        #expect(motion.melodyPulse < 0.001)
        motion.advance(delta: 0.1, bass: 0, lowerMid: 0, mid: 1)
        motion.silence()
        #expect(motion.melodyPulse == 0)
    }

    @Test func melodyAndTrebleMoveWithoutInventingBassKicks() {
        var motion = FluidBackgroundMotion()
        for _ in 0..<60 {
            motion.advance(delta: 1.0 / 30, bass: 0, lowerMid: 0, mid: 0.8, high: 0.9)
        }
        #expect(motion.pulse == 0)
        #expect(motion.melody > 0.5)
        #expect(motion.detail > 0.8)
        #expect(motion.energy > 0)
        for _ in 0..<180 {
            motion.advance(delta: 1.0 / 30, bass: 0, lowerMid: 0)
        }
        #expect(motion.melody < 0.001)
        #expect(motion.detail < 0.001)
        motion.advance(delta: 0.1, bass: 0, lowerMid: 0, mid: 1, high: 1)
        motion.silence()
        #expect(motion.melody == 0)
        #expect(motion.detail == 0)
    }

    @Test func invalidSamplesCannotPoisonTheBackground() {
        var motion = FluidBackgroundMotion()
        motion.advance(delta: .nan, bass: 1, lowerMid: 1)
        motion.advance(delta: 1.0 / 30, bass: .nan, lowerMid: .infinity)
        #expect(motion.pulse == 0)
        #expect(motion.energy == 0)
        #expect(motion.time.isFinite)
    }

    @Test func blurredTextureKeepsPrecisionAndOutputDitherIsStable() async throws {
        let renderer = await ArtworkFlowRenderer.prepared()
        let device = try #require(renderer.device)
        let context = try #require(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        let image = try #require(context.makeImage())
        let texture = try #require(ArtworkFlowPreparation.texture(image, renderer: renderer))
        #expect(texture.pixelFormat == .rgba16Float)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: 128, height: 64, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .shared
        let output = try #require(device.makeTexture(descriptor: descriptor))
        func render() throws -> [UInt8] {
            let command = try #require(renderer.render(target: output, current: texture, previous: nil,
                uniforms: .init(size: SIMD2(128, 64), time: 0, pulse: 0, energy: 0,
                                darkness: 1, blend: 1, contrast: 0)))
            command.waitUntilCompleted()
            #expect(command.status == .completed)
            var pixels = [UInt8](repeating: 0, count: 128 * 64 * 4)
            pixels.withUnsafeMutableBytes { bytes in
                output.getBytes(bytes.baseAddress!, bytesPerRow: 128 * 4,
                    from: MTLRegionMake2D(0, 0, 128, 64), mipmapLevel: 0)
            }
            return pixels
        }
        let first = try render()
        #expect(first == (try render()))
        // A flat near-black field must use neighboring output codes instead of
        // forming a solid 8-bit plateau. Keep its mean within 0.05 of 0.015*255.
        let channel = stride(from: 0, to: first.count, by: 4).map { first[$0] }
        #expect(Set(channel) == Set([UInt8(3), UInt8(4)]))
        let mean = Double(channel.reduce(0) { $0 + Int($1) }) / Double(channel.count)
        #expect(abs(mean - 0.015 * 255) < 0.05)
        #expect(stride(from: 3, to: first.count, by: 4).allSatisfy { first[$0] == 255 })
    }

    @Test func realShaderPreservesArtworkFlowsRespondsToKickAndDarkens() async throws {
        let renderer = await ArtworkFlowRenderer.prepared()
        #expect(!renderer.preparedOnMainThread)
        #expect(renderer.isAvailable)
        let device = try #require(renderer.device)
        let ctx = try #require(CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for (i, color) in [CGColor(red: 0.95, green: 0.18, blue: 0.42, alpha: 1),
                            CGColor(red: 0.95, green: 0.72, blue: 0.32, alpha: 1),
                            CGColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1),
                            CGColor(red: 0.7, green: 0.65, blue: 0.80, alpha: 1)].enumerated() {
            ctx.setFillColor(color)
            ctx.fill(CGRect(x: (i % 2) * 64, y: (i / 2) * 64, width: 64, height: 64))
        }
        let image = try #require(ctx.makeImage())
        let softened = try #require(ArtworkFlowPreparation.soften(image))
        let loadedTexture = try renderer.texture(from: softened)
        let texture = try #require(loadedTexture)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: 300, height: 210, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .shared
        let output = try #require(device.makeTexture(descriptor: descriptor))
        func render(time: Float = 0, pulse: Float = 0, dark: Float = 0, contrast: Float = 0,
                    blend: Float = 1, previous: MTLTexture? = nil) throws -> [UInt8] {
            let command = try #require(renderer.render(target: output, current: texture, previous: previous,
                uniforms: .init(size: SIMD2(1000, 700), time: time, pulse: pulse, energy: 0,
                                darkness: dark, blend: blend, contrast: contrast)))
            command.waitUntilCompleted()
            #expect(command.status == .completed)
            var pixels = [UInt8](repeating: 0, count: 300 * 210 * 4)
            pixels.withUnsafeMutableBytes { ptr in
                output.getBytes(ptr.baseAddress!, bytesPerRow: 300 * 4,
                    from: MTLRegionMake2D(0, 0, 300, 210), mipmapLevel: 0)
            }
            return pixels
        }
        let start = try render()
        let moved = try render(time: 12)
        let kick = try render(time: 12, pulse: 1)
        let dark = try render(time: 12, dark: 1)
        let contrast = try render(time: 12, dark: 1, contrast: 1)
        func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
            Double(zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }) / Double(a.count)
        }
        func brightness(_ p: [UInt8]) -> Double {
            stride(from: 0, to: p.count, by: 4).reduce(0.0) {
                $0 + Double(p[$1]) * 0.114 + Double(p[$1 + 1]) * 0.587 + Double(p[$1 + 2]) * 0.299
            } / Double(300 * 210)
        }
        #expect(difference(start, moved) > 5)
        #expect(difference(moved, kick) > 0.5)
        #expect(brightness(dark) < brightness(moved) * 0.90)
        #expect(brightness(dark) > brightness(moved) * 0.65)
        #expect(brightness(contrast) < brightness(dark))
        // The shader must use the supplied cover, including its spatial colors.
        #expect(Set(stride(from: 0, to: start.count, by: 4).map { start[$0 + 2] }).count > 50)
        ctx.setFillColor(CGColor(red: 0.08, green: 0.20, blue: 0.85, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
        let blueImage = try #require(ctx.makeImage())
        let loadedBlue = try renderer.texture(from: blueImage)
        let blue = try #require(loadedBlue)
        let outgoing = try render(blend: 0, previous: blue)
        let halfway = try render(blend: 0.5, previous: blue)
        #expect(difference(outgoing, start) > 20)
        #expect(difference(halfway, outgoing) > 5)
        #expect(difference(halfway, start) > 5)
        if let path = ProcessInfo.processInfo.environment["CODA_BACKGROUND_PREVIEW"] {
            let frames = [start, moved, kick, dark, contrast]
            let preview = try #require(CGContext(data: nil, width: 1500, height: 210, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            for (index, pixels) in frames.enumerated() {
                var rgba = pixels
                for i in stride(from: 0, to: rgba.count, by: 4) { rgba.swapAt(i, i + 2) }
                let provider = try #require(CGDataProvider(data: Data(rgba) as CFData))
                let frame = try #require(CGImage(width: 300, height: 210, bitsPerComponent: 8,
                    bitsPerPixel: 32, bytesPerRow: 1200, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
                preview.draw(frame, in: CGRect(x: index * 300, y: 0, width: 300, height: 210))
            }
            let destination = try #require(CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                "public.png" as CFString, 1, nil))
            CGImageDestinationAddImage(destination, try #require(preview.makeImage()), nil)
            #expect(CGImageDestinationFinalize(destination))
        }
    }
}
