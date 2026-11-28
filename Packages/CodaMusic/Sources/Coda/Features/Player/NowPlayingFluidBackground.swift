import CoreImage
import MetalKit
import QuartzCore
import SwiftUI
import os

/// Artwork-driven motion, rendered independently of SwiftUI's presentation clock
/// so the surface also animates inside the iPadOS 16 full-screen transition.
struct NowPlayingFluidBackground: View {
    let artwork: PlatformImage?
    let artworkKey: String?
    let colors: ArtworkColors
    let playing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var visibility = MainWindowVisibility.shared

    private var allowsAnimation: Bool {
        #if os(iOS)
        // The native view suspends on didEnterBackground and resumes on
        // didBecomeActive itself. Inside the pre-iOS 18 cover, iPadOS 16 can
        // leave scenePhase at `.background` after the player is shown, which
        // stopped the artwork motion.
        return true
        #else
        // A visible Mac window keeps moving when another app takes focus;
        // occlusion and miniaturising are covered by `visibility`.
        return scenePhase != .background
        #endif
    }

    var body: some View {
        #if os(iOS)
        NowPlayingSoftMistBackground(artwork: artwork, artworkKey: artworkKey, colors: colors)
        #else
        FluidBackgroundSurface(artwork: artwork, artworkKey: artworkKey, colors: colors,
            running: playing && !reduceMotion && allowsAnimation && visibility.isVisible,
            dark: colorScheme == .dark, increasedContrast: contrast == .increased,
            reduceMotion: reduceMotion)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .ignoresSafeArea()
        #endif
    }
}

private struct FluidBackgroundSurface: PlatformViewRepresentable {
    let artwork: PlatformImage?
    let artworkKey: String?
    let colors: ArtworkColors
    let running: Bool
    let dark: Bool
    let increasedContrast: Bool
    let reduceMotion: Bool

    #if os(macOS)
    func makeNSView(context: Context) -> FluidBackgroundNativeView { makeView() }
    func updateNSView(_ view: FluidBackgroundNativeView, context: Context) { update(view) }
    #else
    func makeUIView(context: Context) -> FluidBackgroundNativeView { makeView() }
    func updateUIView(_ view: FluidBackgroundNativeView, context: Context) { update(view) }
    #endif

    private func makeView() -> FluidBackgroundNativeView {
        let view = FluidBackgroundNativeView(frame: .zero)
        update(view)
        return view
    }

    private func update(_ view: FluidBackgroundNativeView) {
        view.update(artwork: artwork, artworkKey: artworkKey, colors: colors, running: running, dark: dark,
                    increasedContrast: increasedContrast, reduceMotion: reduceMotion)
    }
}

/// Time-based onset envelopes: a sustained note settles instead
/// of holding the background at peak expansion. Silence never invents a beat.
struct FluidBackgroundMotion {
    private(set) var time: Double = 0
    private(set) var pulse: Double = 0
    private(set) var energy: Double = 0
    private(set) var melody: Double = 0
    private(set) var melodyPulse: Double = 0
    private(set) var detail: Double = 0

    mutating func advance(delta: Double, bass: Double, lowerMid: Double, mid: Double = 0, high: Double = 0,
                          bassOnset: Double = 0, melodyOnset: Double = 0) {
        guard delta.isFinite else { return }
        let dt = min(max(delta, 0), 0.1)
        guard dt > 0 else { return }
        let bass = bass.isFinite ? min(max(bass, 0), 1) : 0
        let lowerMid = lowerMid.isFinite ? min(max(lowerMid, 0), 1) : 0
        let mid = mid.isFinite ? min(max(mid, 0), 1) : 0
        let high = high.isFinite ? min(max(high, 0), 1) : 0
        let bassOnset = bassOnset.isFinite ? min(max(bassOnset, 0), 1) : 0
        let melodyOnset = melodyOnset.isFinite ? min(max(melodyOnset, 0), 1) : 0
        // Audio-thread spectral onsets survive between display frames.
        pulse = max(bassOnset, pulse * exp(-dt / 0.23))
        melodyPulse = max(melodyOnset, melodyPulse * exp(-dt / 0.28))
        let melodicSample = lowerMid * 0.35 + mid * 0.65
        melody += (melodicSample - melody) * (1 - exp(-dt / (melodicSample > melody ? 0.22 : 0.65)))
        detail += (high - detail) * (1 - exp(-dt / (high > detail ? 0.18 : 0.40)))
        let overall = bass * 0.55 + lowerMid * 0.20 + mid * 0.20 + high * 0.05
        energy += (overall - energy) * (1 - exp(-dt / (overall > energy ? 0.06 : 0.24)))
        time += dt * (1 + energy * 0.20 + pulse * 0.25)
    }

    mutating func silence() {
        pulse = 0
        energy = 0
        melody = 0
        melodyPulse = 0
        detail = 0
    }
}

/// Shared pipeline; every frame changes only a small set of uniforms. Artwork is
/// softened once on a worker, not blurred again at full iPad resolution per frame.
/// See ThirdPartyNotices/MeloX.md for the upstream composition reference.
final class ArtworkFlowRenderer: @unchecked Sendable {
    // Creating the first device/library/pipeline can take hundreds of milliseconds.
    // Even the first caller only creates a task; compilation never runs on the UI thread.
    private static let preparation = Task.detached(priority: .userInitiated) { ArtworkFlowRenderer() }
    static func prepared() async -> ArtworkFlowRenderer { await preparation.value }
    let preparedOnMainThread: Bool
    let device: MTLDevice?
    let queue: MTLCommandQueue?
    private let pipeline: MTLRenderPipelineState?
    private let slots = DispatchSemaphore(value: 3)
    private static let logger = Logger(subsystem: "wow.caicai.coda", category: "ArtworkFlow")

    struct Uniforms {
        var size: SIMD2<Float>
        var time: Float
        var pulse: Float
        var energy: Float
        var darkness: Float
        var blend: Float
        var contrast: Float
        var melody: Float = 0
        var detail: Float = 0
        var melodyPulse: Float = 0
    }

    private init() {
        preparedOnMainThread = Thread.isMainThread
        let device = MTLCreateSystemDefaultDevice()
        self.device = device
        queue = device?.makeCommandQueue()
        do {
            let library = try device?.makeLibrary(source: Self.shader, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library?.makeFunction(name: "artworkFlowVertex")
            descriptor.fragmentFunction = library?.makeFunction(name: "artworkFlowFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipeline = try device?.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            pipeline = nil
            Self.logger.error("Artwork background pipeline failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    var isAvailable: Bool { pipeline != nil && queue != nil }

    func texture(from image: CGImage) throws -> MTLTexture? {
        guard let device else { return nil }
        return try MTKTextureLoader(device: device).newTexture(cgImage: image, options: [
            .SRGB: false, .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue)
        ])
    }

    /// Returns the command buffer so host checks can read the real rendered pixels.
    @discardableResult
    func render(target: MTLTexture, current: MTLTexture, previous: MTLTexture?,
                uniforms: Uniforms, drawable: CAMetalDrawable? = nil) -> MTLCommandBuffer? {
        guard let pipeline, let queue, slots.wait(timeout: .now()) == .success else { return nil }
        guard let command = queue.makeCommandBuffer() else { slots.signal(); return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            slots.signal()
            return nil
        }
        var uniforms = uniforms
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentTexture(current, index: 0)
        encoder.setFragmentTexture(previous ?? current, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        if let drawable { command.present(drawable) }
        let slots = slots
        command.addCompletedHandler { _ in slots.signal() }
        command.commit()
        return command
    }

    /// Keeping MSL as a library source also supports this shared Swift package on
    /// iPadOS 16, without SwiftUI's iOS 17+ layerEffect or a bundled metallib lookup.
    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct Vertex { float4 position [[position]]; float2 uv; };
    struct Uniforms {
        float2 size;
        float time, pulse, energy, darkness, blend, contrast;
        float melody, detail, melodyPulse;
    };
    vertex Vertex artworkFlowVertex(uint id [[vertex_id]]) {
        float2 p = float2((id << 1) & 2, id & 2);
        return { float4(p * 2.0 - 1.0, 0.0, 1.0), float2(p.x, 1.0 - p.y) };
    }
    float2 rotatePoint(float2 p, float angle) {
        float s = sin(angle), c = cos(angle);
        return float2(c * p.x + s * p.y, c * p.y - s * p.x);
    }
    float3 coverLayers(texture2d<float> image, float2 uv, constant Uniforms &u) {
        constexpr sampler sampling(coord::normalized, address::clamp_to_edge, filter::linear);
        float2 point = (uv - 0.5) * u.size;
        float side = max(u.size.x, u.size.y);
        float t = u.time;
        float zoom = 1.0 + u.pulse * 0.16 + u.energy * 0.025 + u.melodyPulse * 0.07;
        // Independent, slow rotations reveal several regions of the same cover.
        // The diagonal-sized base never exposes a corner in either orientation.
        float2 base = rotatePoint(point, t * 0.065) / (length(u.size) * zoom) + 0.5;
        float3 color = image.sample(sampling, base).rgb;
        for (uint i = 1; i < 3; ++i) {
            float angle = i == 1 ? -t * 0.085 + 1.7 : t * 0.055 + 3.8;
            float2 offset = i == 1 ? float2(-0.36, -0.27) : float2(0.32, 0.30);
            offset += float2(sin(t * 0.09 + i), cos(t * 0.07 + i)) * (0.12 + u.melody * 0.06);
            float2 sampleUV = rotatePoint(point / (side * zoom) - offset, angle) + 0.5;
            float edge = min(min(sampleUV.x, sampleUV.y), min(1.0 - sampleUV.x, 1.0 - sampleUV.y));
            float alpha = smoothstep(0.0, 0.24, edge) * 0.78;
            color = mix(color, image.sample(sampling, sampleUV).rgb, alpha);
        }
        return color;
    }
    float3 artworkComposition(texture2d<float> image, float2 screenUV, float2 flowUV, constant Uniforms &u) {
        constexpr sampler sampling(coord::normalized, address::clamp_to_edge, filter::linear);
        float3 flow = coverLayers(image, flowUV, u);
        // Drift and tilt the softened cover without warping its large shapes.
        float2 imageSize = float2(image.get_width(), image.get_height());
        float shortSide = min(u.size.x, u.size.y);
        float2 motifSize = imageSize / max(imageSize.x, imageSize.y) * shortSide * 1.42;
        float wide = smoothstep(1.0, 1.6, u.size.x / u.size.y);
        float2 center = float2(mix(0.5, 0.65, wide), 0.48);
        float t = u.time;
        float2 drift = float2(sin(t * 0.27) * 0.085, sin(t * 0.21) * 0.055) * shortSide;
        float tilt = sin(t * 0.19) * 0.11;
        float breathing = 1.0 + u.pulse * 0.055;
        float2 point = (screenUV - center) * u.size - drift;
        float2 motifUV = rotatePoint(point, tilt) / (motifSize * breathing) + 0.5;
        // Feather the cover into the moving colors so its rectangular edge disappears.
        float2 margin = min(motifUV, 1.0 - motifUV);
        float2 feather = smoothstep(float2(0.0), float2(0.18), margin);
        return mix(flow, image.sample(sampling, motifUV).rgb, 0.54 * feather.x * feather.y);
    }
    fragment float4 artworkFlowFragment(Vertex v [[stage_in]],
        constant Uniforms &u [[buffer(0)]], texture2d<float> current [[texture(0)]],
        texture2d<float> previous [[texture(1)]]) {
        float2 uv = v.uv;
        float2 p = uv - 0.5;
        float t = u.time;
        // A continuous warp stretches the cover into broad folds. The kick
        // briefly increases the fold, then decays without a white flash.
        float fold = 0.065 + u.energy * 0.025 + u.pulse * 0.10 + u.melody * 0.06 + u.melodyPulse * 0.045;
        // Treble adds a small local drift, never whole-surface expansion or flashing.
        uv += float2(sin(p.y * 7.0 + t * 0.31), cos(p.x * 6.0 - t * 0.27))
            * (u.detail * 0.008);
        uv += float2(sin(p.y * 4.8 + t * 0.13), cos(p.x * 4.1 - t * 0.11)) * fold;
        uv = rotatePoint(uv - 0.5, sin(t * 0.10) * 0.13 + u.pulse * 0.065) * 0.84 + 0.5;
        float3 color;
        if (u.blend >= 0.999) color = artworkComposition(current, v.uv, uv, u);
        else if (u.blend <= 0.001) color = artworkComposition(previous, v.uv, uv, u);
        else color = mix(artworkComposition(previous, v.uv, uv, u),
                         artworkComposition(current, v.uv, uv, u), u.blend);
        float luminance = dot(color, float3(0.299, 0.587, 0.114));
        color = clamp(luminance + (color - luminance) * 1.65, 0.0, 1.0);
        // The system appearance controls brightness, keeping the cover's hue.
        color *= mix(0.98, 0.73, u.darkness);
        // Compress near-white covers to leave room for the white player chrome.
        float peak = max(color.r, max(color.g, color.b));
        float brightness = dot(color, float3(0.299, 0.587, 0.114));
        // In light appearance a saturated channel can stay brighter than a near-white region.
        float colorAllowance = 0.65 * (1.0 - u.darkness) * (1.0 - u.contrast);
        float highlight = mix(peak, brightness, colorAllowance);
        float ceiling = mix(0.80, 0.68, u.darkness) - u.contrast * 0.10;
        color *= min(1.0, ceiling / max(highlight, 0.001));
        float lightBottomShade = smoothstep(0.55, 1.0, v.uv.y) * 0.05;
        float darkBottomShade = smoothstep(0.15, 1.0, v.uv.y) * 0.14;
        float bottomShade = mix(lightBottomShade, darkBottomShade, u.darkness);
        float edgeShade = smoothstep(0.28, 0.75, length(p)) * (0.10 * u.darkness);
        color *= 1.0 - bottomShade - edgeShade - u.contrast * 0.10;
        // Break up 8-bit output bands after all grading/shading. Screen-space
        // noise stays fixed when paused/reduced-motion and never flickers with time.
        float noise = fract(52.9829189 * fract(dot(v.position.xy,
            float2(0.06711056, 0.00583715)))) - 0.5;
        color = clamp(max(color, 0.015) + noise / 255.0, 0.0, 1.0);
        return float4(color, 1.0);
    }
    """
}

enum ArtworkFlowPreparation {
    private static let context = CIContext(options: [
        .cacheIntermediates: false, .workingFormat: CIFormat.RGBAh.rawValue
    ])

    private static func softenedImage(_ image: CGImage) -> CIImage {
        let fit = min(1, 320 / CGFloat(max(image.width, image.height)))
        let width = max(1, (CGFloat(image.width) * fit).rounded())
        let height = max(1, (CGFloat(image.height) * fit).rounded())
        let source = CIImage(cgImage: image).transformed(by: CGAffineTransform(
            scaleX: width / CGFloat(image.width), y: height / CGFloat(image.height)))
        return source.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [
            kCIInputRadiusKey: 14.0
        ]).cropped(to: source.extent)
    }

    static func soften(_ image: CGImage) -> CGImage? {
        let softened = softenedImage(image)
        return context.createCGImage(softened, from: softened.extent)
    }

    /// Keep blurred gradients in half-float precision until the final display pass.
    /// Upload directly: the ordinary CGImage texture-loader path quantizes to 8 bits.
    static func texture(_ image: CGImage, renderer: ArtworkFlowRenderer) -> MTLTexture? {
        guard let device = renderer.device else { return nil }
        let softened = softenedImage(image)
        let width = max(1, Int(ceil(softened.extent.width)))
        let height = max(1, Int(ceil(softened.extent.height)))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
            width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let rowBytes = width * 8
        var pixels = [UInt16](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            guard let address = bytes.baseAddress else { return }
            context.render(softened, toBitmap: address, rowBytes: rowBytes,
                bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBAh,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                withBytes: address, bytesPerRow: rowBytes)
        }
        return texture
    }
}

/// A small bounded cache survives closing the player. Returning to the same cover
/// reuses the softened GPU texture rather than competing with the transition again.
actor ArtworkFlowTextureCache {
    static let shared = ArtworkFlowTextureCache()
    private var tasks: [String: Task<MTLTexture?, Never>] = [:]
    private var order: [String] = []

    func texture(for image: CGImage, key: String?, renderer: ArtworkFlowRenderer) async -> MTLTexture? {
        let key = key.map { "\($0):\(image.width)x\(image.height)" }
        if let key, let task = tasks[key] { return await task.value }
        let task = Task.detached(priority: .userInitiated) {
            ArtworkFlowPreparation.texture(image, renderer: renderer)
        }
        if let key {
            tasks[key] = task
            order.append(key)
            while order.count > 4 { tasks.removeValue(forKey: order.removeFirst()) }
        }
        let texture = await task.value
        if texture == nil, let key {
            tasks.removeValue(forKey: key)
            order.removeAll { $0 == key }
        }
        return texture
    }
}

/// Never queue up stale background frames, and never acquire a drawable on the
/// main thread. CAMetalLayer.nextDrawable can wait for the compositor, especially
/// while the whole player is sliding in or out.
final class ArtworkFlowFrameProducer: @unchecked Sendable {
    // Only nextDrawable/present touch this layer on the worker. Geometry stays
    // on the main actor; the command retains its textures through completion.
    struct Frame: @unchecked Sendable {
        let surface: CAMetalLayer
        let renderer: ArtworkFlowRenderer
        let current: MTLTexture
        let previous: MTLTexture?
        let uniforms: ArtworkFlowRenderer.Uniforms

        func draw() {
            guard let drawable = surface.nextDrawable() else { return }
            renderer.render(target: drawable.texture, current: current, previous: previous,
                            uniforms: uniforms, drawable: drawable)
        }
    }

    private let queue = DispatchQueue(label: "wow.caicai.coda.artwork-flow", qos: .userInitiated,
                                      autoreleaseFrequency: .workItem)
    private let available = DispatchSemaphore(value: 1)

    @discardableResult
    func submit(_ frame: @escaping @Sendable () -> Void) -> Bool {
        guard available.wait(timeout: .now()) == .success else { return false }
        queue.async { [self] in
            defer { available.signal() }
            frame()
        }
        return true
    }
}

@MainActor
private final class FluidBackgroundLinkTarget: NSObject {
    weak var view: FluidBackgroundNativeView?
    @objc func step(_ link: CADisplayLink) { view?.step(link) }
}

@MainActor
final class FluidBackgroundNativeView: PlatformView {
    private var renderer: ArtworkFlowRenderer?
    private var surface: CAMetalLayer?
    private let producer = ArtworkFlowFrameProducer()
    private let fallback = CAGradientLayer()
    private let target = FluidBackgroundLinkTarget()
    private var initialization: Task<Void, Never>?
    private var pendingArtwork: (image: CGImage, id: ObjectIdentifier, key: String?)?
    private var link: CADisplayLink?
    private var lastTime: CFTimeInterval?
    private var running = false
    private var needsFrame = false
    private var reducedMotion = false
    private var motion = FluidBackgroundMotion()
    private var artworkID: ObjectIdentifier?
    private var preparation: Task<Void, Never>?
    private var current: MTLTexture?
    private var previous: MTLTexture?
    private var transitionStart: CFTimeInterval?
    private var dark: Float = 0
    private var targetDark: Float = 0
    private var increasedContrast = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        #if os(macOS)
        wantsLayer = true
        layer?.addSublayer(fallback)
        #else
        backgroundColor = .black
        isUserInteractionEnabled = false
        layer.addSublayer(fallback)
        NotificationCenter.default.addObserver(self, selector: #selector(suspendRendering),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resumeRendering),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(rotationDidEnd),
            name: CoverRotation.didEnd, object: nil)
        #endif
        target.view = self
        initialization = Task { [weak self] in
            let renderer = await ArtworkFlowRenderer.prepared()
            guard !Task.isCancelled, let self, renderer.isAvailable else { return }
            self.renderer = renderer
            let surface = CAMetalLayer()
            surface.device = renderer.device
            surface.pixelFormat = .bgra8Unorm
            surface.framebufferOnly = true
            surface.isOpaque = true
            surface.isHidden = true
            surface.presentsWithTransaction = false
            #if os(macOS)
            self.layer?.addSublayer(surface)
            #else
            self.layer.addSublayer(surface)
            #endif
            self.surface = surface
            self.layoutSurface()
            if let pending = self.pendingArtwork {
                self.pendingArtwork = nil
                self.prepare(pending.image, id: pending.id, key: pending.key)
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    deinit {
        NotificationCenter.default.removeObserver(self)
        link?.invalidate()
        initialization?.cancel()
        preparation?.cancel()
    }

    #if os(iOS)
    @objc private func suspendRendering() {
        link?.invalidate()
        link = nil
        lastTime = nil
    }

    @objc private func resumeRendering() {
        lastTime = nil
        updateLink()
        drawFrame()
    }

    @objc private func rotationDidEnd() { layoutSurface() }
    #endif

    func update(artwork: PlatformImage?, artworkKey: String? = nil, colors: ArtworkColors, running: Bool,
                dark: Bool, increasedContrast: Bool, reduceMotion: Bool) {
        let redraw = self.running != running || self.increasedContrast != increasedContrast
            || self.reducedMotion != reduceMotion || (reduceMotion && targetDark != (dark ? 1 : 0))
        self.running = running
        self.reducedMotion = reduceMotion
        self.increasedContrast = increasedContrast
        targetDark = dark ? 1 : 0
        if reduceMotion || window == nil { self.dark = targetDark }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fallback.colors = [PlatformColor(colors.primary).cgColor, PlatformColor(colors.secondary).cgColor]
        fallback.startPoint = .zero
        fallback.endPoint = CGPoint(x: 1, y: 1)
        fallback.opacity = dark ? 0.73 : 0.98
        CATransaction.commit()
        if let artwork {
            let id = ObjectIdentifier(artwork)
            if id != artworkID, let image = artwork.cgImageRef {
                artworkID = id
                if renderer != nil { prepare(image, id: id, key: artworkKey) }
                else { pendingArtwork = (image, id, artworkKey) }
            }
        }
        if !running { motion.silence() }
        if reduceMotion { previous = nil; transitionStart = nil }
        updateLink()
        if redraw { drawFrame() }
    }

    private func prepare(_ image: CGImage, id: ObjectIdentifier, key: String?) {
        preparation?.cancel()
        guard let renderer else { return }
        preparation = Task { [weak self] in
            let texture = await ArtworkFlowTextureCache.shared.texture(for: image, key: key, renderer: renderer)
            guard !Task.isCancelled, let self, self.artworkID == id, let texture else { return }
            self.previous = self.reducedMotion ? nil : self.current
            self.current = texture
            self.transitionStart = self.previous == nil ? nil : CACurrentMediaTime()
            self.updateLink()
            self.drawFrame()
        }
    }

    #if os(macOS)
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() { super.layout(); layoutSurface() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateLink(); drawFrame() }
    #else
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }
    override func layoutSubviews() { super.layoutSubviews(); layoutSurface() }
    override func didMoveToWindow() { super.didMoveToWindow(); updateLink(); drawFrame() }
    #endif

    private func layoutSurface() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if fallback.frame != bounds { fallback.frame = bounds }
        if surface?.frame != bounds { surface?.frame = bounds }
        CATransaction.commit()
        guard let surface, bounds.width > 0, bounds.height > 0 else { return }
        let limit: CGFloat = ProcessInfo.processInfo.isLowPowerModeEnabled ? 640 : 960
        let fit = min(1, limit / max(bounds.width, bounds.height))
        let size = CGSize(width: max(1, (bounds.width * fit).rounded()),
                          height: max(1, (bounds.height * fit).rounded()))
        // Reassigning drawableSize on every SwiftUI layout invalidates drawable
        // storage even when a slide changes only the position of the player.
        guard surface.drawableSize != size else { return }
        #if os(iOS)
        // A new drawable stays black until its frame is presented. While the
        // window turns, keep the current frame stretched to the new bounds and
        // resize once the rotation ends.
        if CoverRotation.isActive, current != nil, !surface.isHidden { return }
        #endif
        surface.drawableSize = size
        drawFrame()
    }

    private func updateLink() {
        #if os(iOS)
        // Also guard native callbacks (layout/artwork completion) while the
        // SwiftUI scene environment is still catching up with UIKit.
        guard UIApplication.shared.applicationState != .background else {
            suspendRendering()
            return
        }
        #endif
        guard window != nil, surface != nil, current != nil,
              running || needsFrame || previous != nil || abs(dark - targetDark) > 0.001 else {
            link?.invalidate()
            link = nil
            lastTime = nil
            return
        }
        guard link == nil else { return }
        #if os(macOS)
        let display = displayLink(target: target, selector: #selector(FluidBackgroundLinkTarget.step(_:)))
        #else
        let display = CADisplayLink(target: target, selector: #selector(FluidBackgroundLinkTarget.step(_:)))
        display.preferredFramesPerSecond = 30
        #endif
        display.add(to: .main, forMode: .common)
        link = display
    }

    fileprivate func step(_ display: CADisplayLink) {
        let now = CACurrentMediaTime()
        guard let lastTime else { self.lastTime = now; return }
        guard now - lastTime >= 1.0 / 32 else { return }
        let delta = min(now - lastTime, 0.1)
        self.lastTime = now
        dark += (targetDark - dark) * Float(1 - exp(-delta / 0.25))
        if running {
            let spectrum = AudioSpectrum.shared
            let live = spectrum.tapState == .tapped && spectrum.isLive
            let onsets = spectrum.takeOnsets()
            motion.advance(delta: delta, bass: live ? Double(spectrum.level(at: 0)) : 0,
                           lowerMid: live ? Double(spectrum.level(at: 1)) : 0,
                           mid: live ? Double(spectrum.level(at: 2)) : 0,
                           high: live ? Double(spectrum.level(at: 3)) : 0,
                           bassOnset: live ? Double(onsets.bass) : 0,
                           melodyOnset: live ? Double(onsets.melody) : 0)
        }
        drawFrame()
        updateLink()
    }

    private func drawFrame() {
        #if os(iOS)
        guard UIApplication.shared.applicationState != .background else { return }
        #endif
        guard window != nil, let renderer, let surface, let current,
              bounds.width > 0, bounds.height > 0 else { return }
        let blend = transitionStart.map { min(1, max(0, (CACurrentMediaTime() - $0) / 0.6)) } ?? 1
        let uniforms = ArtworkFlowRenderer.Uniforms(size: SIMD2(Float(bounds.width), Float(bounds.height)),
            time: Float(motion.time), pulse: Float(motion.pulse), energy: Float(motion.energy),
            darkness: dark, blend: Float(blend * blend * (3 - 2 * blend)), contrast: increasedContrast ? 1 : 0,
            melody: Float(motion.melody), detail: Float(motion.detail), melodyPulse: Float(motion.melodyPulse))
        let previous = previous
        // CAMetalLayer must be visible before nextDrawable, but no Metal wait
        // or command encoding is allowed to hold up the entrance/exit animation.
        if surface.isHidden {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            surface.isHidden = false
            CATransaction.commit()
        }
        let frame = ArtworkFlowFrameProducer.Frame(surface: surface, renderer: renderer,
            current: current, previous: previous, uniforms: uniforms)
        needsFrame = !producer.submit { frame.draw() }
        // A paused/reduced-motion cover change still retries if the worker was
        // occupied. No old frame is queued, and a static update cannot be lost.
        if needsFrame { updateLink() }
        if blend >= 1 { self.previous = nil; transitionStart = nil }
    }
}
