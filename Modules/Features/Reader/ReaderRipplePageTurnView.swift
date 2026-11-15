import Metal
import MetalKit
import UIKit

public struct ReaderRippleWaveform: Sendable {
    /// Maximum UV-space displacement. Values are clamped to 0...0.08.
    public var amplitude: Float
    /// Oscillation frequency across the wavefront, in radians per UV unit.
    public var frequency: Float
    /// Phase advance over a complete gesture, in radians.
    public var speed: Float
    /// Exponential attenuation away from the moving front.
    public var decay: Float

    public init(
        amplitude: Float = 0.018,
        frequency: Float = 34,
        speed: Float = 18,
        decay: Float = 22
    ) {
        self.amplitude = amplitude
        self.frequency = frequency
        self.speed = speed
        self.decay = decay
    }

    public static let standard = ReaderRippleWaveform()
}

/// A standalone Metal overlay for turning between two pre-rendered page images.
/// Call `setPages` only when the page pair changes, then call `update` with
/// normalized gesture values. A nil texture or unavailable renderer stays
/// transparent so the host can keep its ordinary page-turn implementation.
@MainActor
public final class ReaderRipplePageTurnView: UIView, @preconcurrency MTKViewDelegate {
    public enum Failure: Error, Sendable {
        case metalDeviceUnavailable
        case defaultLibraryUnavailable
        case shaderFunctionsUnavailable
        case pipelineCreationFailed
        case commandQueueUnavailable
        case missingPageTexture
        case pageTextureCreationFailed
    }

    public private(set) var failure: Failure?
    public var onFailure: (@MainActor (Failure) -> Void)?
    public var isRendererAvailable: Bool { gpuResources != nil && metalView != nil }

    private static let maximumTextureDimension = 2_048
    private static let textureCacheCostLimit = 40 * 1_024 * 1_024
    private static let textureCacheEntryLimit = 4

    private struct GPUResources {
        let device: any MTLDevice
        let library: any MTLLibrary
        let pipeline: any MTLRenderPipelineState
        let commandQueue: any MTLCommandQueue
    }

    private enum GPUResourceResult {
        case ready(GPUResources)
        case failed(Failure)
    }

    private struct TextureCacheEntry {
        let image: UIImage
        let texture: any MTLTexture
        let cost: Int
        var lastAccess: UInt64
    }

    private struct Uniforms {
        var originProgress: SIMD4<Float>
        var direction: SIMD4<Float>
        var waveform: SIMD4<Float>
    }

    private static var gpuResourceCache: [ObjectIdentifier: GPUResourceResult] = [:]

    private var gpuResources: GPUResources?
    private var textureLoader: MTKTextureLoader?
    private var metalView: MTKView?
    private var isRendererAttached = false
    private var oldTexture: (any MTLTexture)?
    private var newTexture: (any MTLTexture)?
    private var textureCache: [ObjectIdentifier: TextureCacheEntry] = [:]
    private var textureCacheCost = 0
    private var cacheAccessCounter: UInt64 = 0
    private var uniforms = Uniforms(
        originProgress: SIMD4<Float>(0.5, 0.5, 0, 0.012),
        direction: SIMD4<Float>(1, 0, 34, 18),
        waveform: SIMD4<Float>(0.018, 22, 0, 0)
    )

    public override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        configureRenderer()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureRenderer()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        metalView?.frame = bounds
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            detachRenderer()
        } else {
            attachRenderer()
        }
    }

    /// Replaces the page pair. Image rasterization and texture creation happen
    /// here, never in the gesture-progress update path.
    @discardableResult
    public func setPages(oldPage: UIImage?, newPage: UIImage?) -> Bool {
        guard let oldPage, let newPage else {
            oldTexture = nil
            newTexture = nil
            report(.missingPageTexture)
            requestRender()
            return false
        }

        guard let oldTexture = texture(for: oldPage),
              let newTexture = texture(for: newPage) else {
            self.oldTexture = nil
            self.newTexture = nil
            report(.pageTextureCreationFailed)
            requestRender()
            return false
        }

        self.oldTexture = oldTexture
        self.newTexture = newTexture
        failure = nil
        requestRender()
        return true
    }

    /// Updates gesture state. `origin` is normalized to 0...1 in view space;
    /// `direction` is normalized internally and points in the wave's travel direction.
    public func update(
        progress: CGFloat,
        origin: CGPoint,
        direction: SIMD2<Float>,
        waveform: ReaderRippleWaveform = .standard
    ) {
        let progressValue = progress.isFinite ? Float(min(max(progress, 0), 1)) : 0
        let originX = Self.normalized(origin.x)
        let originY = Self.normalized(origin.y)
        let dx = direction.x.isFinite ? direction.x : 0
        let dy = direction.y.isFinite ? direction.y : 0
        let directionLength = sqrt(dx * dx + dy * dy)
        let axis: SIMD2<Float>
        if directionLength > 0.0001 {
            axis = SIMD2<Float>(dx / directionLength, dy / directionLength)
        } else {
            axis = SIMD2<Float>(1, 0)
        }

        let amplitude = Self.clamped(waveform.amplitude, to: 0...0.08, fallback: 0.018)
        let frequency = Self.clamped(waveform.frequency, to: 0...128, fallback: 34)
        let speed = Self.clamped(waveform.speed, to: 0...100, fallback: 18)
        let decay = Self.clamped(waveform.decay, to: 0...64, fallback: 22)

        uniforms = Uniforms(
            originProgress: SIMD4<Float>(originX, originY, progressValue, 0.012),
            direction: SIMD4<Float>(axis.x, axis.y, frequency, speed),
            waveform: SIMD4<Float>(amplitude, decay, 0, 0)
        )
        requestRender()
    }

    /// Stops delegate callbacks while the view is detached. Reattachment is
    /// automatic when this view returns to a window.
    public func detachRenderer() {
        guard let metalView else { return }
        metalView.delegate = nil
        isRendererAttached = false
    }

    /// Reattaches only when the view is in a window; no display link is created.
    public func attachRenderer() {
        guard window != nil, let metalView, !isRendererAttached else { return }
        metalView.delegate = self
        isRendererAttached = true
        metalView.setNeedsDisplay()
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        guard isRendererAttached,
              view === metalView,
              let resources = gpuResources,
              let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let commandBuffer = resources.commandQueue.makeCommandBuffer() else {
            return
        }

        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        if let oldTexture, let newTexture {
            var frameUniforms = uniforms
            encoder.setRenderPipelineState(resources.pipeline)
            encoder.setFragmentTexture(oldTexture, index: 0)
            encoder.setFragmentTexture(newTexture, index: 1)
            encoder.setFragmentBytes(
                &frameUniforms,
                length: MemoryLayout<Uniforms>.stride,
                index: 0
            )
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func configureRenderer() {
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw

        guard let device = MTLCreateSystemDefaultDevice() else {
            report(.metalDeviceUnavailable)
            return
        }

        switch Self.resources(for: device) {
        case let .failed(reason):
            report(reason)
        case let .ready(resources):
            gpuResources = resources
            textureLoader = MTKTextureLoader(device: device)

            let view = MTKView(frame: bounds, device: device)
            view.backgroundColor = .clear
            view.isOpaque = false
            view.layer.isOpaque = false
            view.colorPixelFormat = .bgra8Unorm
            view.framebufferOnly = true
            view.depthStencilPixelFormat = .invalid
            view.sampleCount = 1
            view.clearColor = MTLClearColorMake(0, 0, 0, 0)
            view.isPaused = true
            view.enableSetNeedsDisplay = true
            view.delegate = nil
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            metalView = view
            addSubview(view)
        }
    }

    private static func resources(for device: any MTLDevice) -> GPUResourceResult {
        let key = ObjectIdentifier(device as AnyObject)
        if let cached = gpuResourceCache[key] { return cached }

        guard let library = device.makeDefaultLibrary() else {
            let result = GPUResourceResult.failed(.defaultLibraryUnavailable)
            gpuResourceCache[key] = result
            return result
        }
        guard let vertex = library.makeFunction(name: "readerRippleVertex"),
              let fragment = library.makeFunction(name: "readerRippleFragment") else {
            let result = GPUResourceResult.failed(.shaderFunctionsUnavailable)
            gpuResourceCache[key] = result
            return result
        }
        guard let commandQueue = device.makeCommandQueue() else {
            let result = GPUResourceResult.failed(.commandQueueUnavailable)
            gpuResourceCache[key] = result
            return result
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        if let attachment = descriptor.colorAttachments[0] {
            attachment.isBlendingEnabled = true
            attachment.rgbBlendOperation = .add
            attachment.alphaBlendOperation = .add
            attachment.sourceRGBBlendFactor = .sourceAlpha
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }

        do {
            let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            let result = GPUResourceResult.ready(
                GPUResources(
                    device: device,
                    library: library,
                    pipeline: pipeline,
                    commandQueue: commandQueue
                )
            )
            gpuResourceCache[key] = result
            return result
        } catch {
            let result = GPUResourceResult.failed(.pipelineCreationFailed)
            gpuResourceCache[key] = result
            return result
        }
    }

    private func texture(for image: UIImage) -> (any MTLTexture)? {
        let key = ObjectIdentifier(image)
        cacheAccessCounter &+= 1
        if var cached = textureCache[key], cached.image === image {
            cached.lastAccess = cacheAccessCounter
            textureCache[key] = cached
            return cached.texture
        }
        guard let textureLoader,
              let cgImage = normalizedCGImage(from: image) else {
            return nil
        }

        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: false,
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .origin: MTKTextureLoader.Origin.topLeft
        ]
        guard let texture = try? textureLoader.newTexture(cgImage: cgImage, options: options) else {
            return nil
        }

        let cost = texture.width * texture.height * 4
        guard cost <= Self.textureCacheCostLimit else { return texture }
        while textureCache.count >= Self.textureCacheEntryLimit ||
                textureCacheCost + cost > Self.textureCacheCostLimit {
            guard let oldestKey = textureCache.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key,
                  let removed = textureCache.removeValue(forKey: oldestKey) else {
                break
            }
            textureCacheCost -= removed.cost
        }
        textureCache[key] = TextureCacheEntry(
            image: image,
            texture: texture,
            cost: cost,
            lastAccess: cacheAccessCounter
        )
        textureCacheCost += cost
        return texture
    }

    private func normalizedCGImage(from image: UIImage) -> CGImage? {
        let pointSize = image.size
        let pixelWidth = pointSize.width * image.scale
        let pixelHeight = pointSize.height * image.scale
        guard pixelWidth.isFinite, pixelHeight.isFinite,
              pixelWidth > 0, pixelHeight > 0 else {
            return nil
        }

        let scale = min(1, CGFloat(Self.maximumTextureDimension) / max(pixelWidth, pixelHeight))
        let width = max(1, Int((pixelWidth * scale).rounded(.up)))
        let height = max(1, Int((pixelHeight * scale).rounded(.up)))
        let targetSize = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard

        let normalized = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return normalized.cgImage
    }

    private func requestRender() {
        guard isRendererAttached else { return }
        metalView?.setNeedsDisplay()
    }

    private func report(_ reason: Failure) {
        failure = reason
        onFailure?(reason)
    }

    private static func normalized(_ value: CGFloat) -> Float {
        guard value.isFinite else { return 0.5 }
        return Float(min(max(value, 0), 1))
    }

    private static func clamped(
        _ value: Float,
        to range: ClosedRange<Float>,
        fallback: Float
    ) -> Float {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
