import Foundation

/// A preference selects real engines, not a label on the same player.
enum VideoKernelPreference: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case ksPlayer
    case avFoundation

    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: localized("自動（優先 KSPlayer）")
        case .ksPlayer: "KSPlayer · FFmpeg"
        case .avFoundation: "AVFoundation"
        }
    }
    var label: String { title }
}

/// No engine is created when selecting a policy. Explicit legacy true means KS then AV;
/// false means AV only; nil leaves the typed persisted preference in charge.
struct VideoKernelPolicy: Equatable, Sendable {
    enum Kernel: Equatable, Sendable {
        case ksPlayer, avFoundation

        var title: String { self == .ksPlayer ? "KSPlayer · FFmpeg" : "AVFoundation" }
    }

    let preference: VideoKernelPreference
    init(preference: VideoKernelPreference, legacyOverride: Bool? = nil) {
        self.preference = legacyOverride.map { $0 ? .automatic : .avFoundation } ?? preference
    }
    var initialKernel: Kernel { preference == .avFoundation ? .avFoundation : .ksPlayer }
    var allowsAVFallback: Bool { preference == .automatic }
}

/// Pure, per-controller continuation state. Cancellation alone is insufficient: a resolver,
/// KVO delivery or seek completion may already be queued when an episode is replaced/closed.
struct VideoPlaybackLoadState: Sendable {
    struct Token: Equatable, Sendable { fileprivate let id = UUID() }
    struct SeekToken: Equatable, Sendable {
        fileprivate let load: Token
        fileprivate let id = UUID()
    }

    let policy: VideoKernelPolicy
    private(set) var token: Token?
    private(set) var kernel: VideoKernelPolicy.Kernel
    private(set) var usedAVFallback = false
    private(set) var wantsPlayback = true
    private(set) var isPreparing = true
    private var receivedReady = false
    private var seekToken: SeekToken?

    init(policy: VideoKernelPolicy) {
        self.policy = policy
        kernel = policy.initialKernel
    }

    /// Internal link refresh gets a new generation but keeps the fallback budget and intent.
    /// Only an explicit new episode/retry starts another KS-first attempt.
    mutating func begin(preservingContinuation: Bool = false) -> Token {
        if !preservingContinuation || token == nil {
            kernel = policy.initialKernel
            usedAVFallback = false
            wantsPlayback = true
        }
        let next = Token()
        token = next
        seekToken = nil
        isPreparing = true
        receivedReady = false
        return next
    }

    func accepts(_ candidate: Token, kernel: VideoKernelPolicy.Kernel? = nil) -> Bool {
        token == candidate && (kernel == nil || self.kernel == kernel)
    }

    mutating func takeAVFallback(for candidate: Token) -> Bool {
        guard accepts(candidate, kernel: .ksPlayer), policy.allowsAVFallback, !usedAVFallback else { return false }
        usedAVFallback = true
        kernel = .avFoundation
        seekToken = nil
        receivedReady = false
        isPreparing = true
        return true
    }

    mutating func receiveReady(for candidate: Token, kernel: VideoKernelPolicy.Kernel) -> Bool {
        guard accepts(candidate, kernel: kernel), !receivedReady else { return false }
        receivedReady = true
        return true
    }

    mutating func finishPreparing(for candidate: Token) -> Bool {
        guard accepts(candidate), receivedReady, isPreparing else { return false }
        isPreparing = false
        return true
    }

    mutating func setWantsPlayback(_ value: Bool) {
        guard token != nil else { return }
        wantsPlayback = value
    }

    mutating func beginSeek() -> SeekToken? {
        guard let token else { return nil }
        let next = SeekToken(load: token)
        seekToken = next
        return next
    }

    func accepts(_ candidate: SeekToken) -> Bool {
        token == candidate.load && seekToken == candidate
    }

    mutating func close() {
        token = nil
        seekToken = nil
        wantsPlayback = false
        isPreparing = true
    }
}
