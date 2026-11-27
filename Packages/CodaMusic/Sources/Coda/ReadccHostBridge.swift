import Foundation

/// The only cross-module contract. No Readcc models, credentials or playback URLs cross it.
@MainActor
public enum ReadccHostBridge {
    public enum Owner: Equatable, Sendable { case none, readcc, coda }
    public enum InitialDestination: Equatable, Sendable { case home, library }
    /// The actual upstream providers, not a separate host resolver or entitlement bypass.
    public static var providerIDs: Set<String> {
        Set(MusicProvider.allCases.map(\.rawValue))
    }

    /// Kept separate from the singleton engines so ownership transitions are unit-testable.
    @MainActor
    public final class AudioOwnership {
        public private(set) var owner: Owner = .none
        private var transitioning = false
        private var stopReadcc: @MainActor () -> Void = {}
        private var stopCoda: @MainActor () -> Void = {}

        public init() {}
        public func installReadccStop(_ stop: @escaping @MainActor () -> Void) { stopReadcc = stop }
        public func installCodaStop(_ stop: @escaping @MainActor () -> Void) { stopCoda = stop }

        /// Synchronous main-actor transfer: the outgoing engine has stopped before return.
        /// Same-owner and reentrant requests cannot invoke the outgoing callback twice.
        @discardableResult
        public func claim(_ next: Owner) -> Bool {
            guard !transitioning, owner != next else { return false }
            transitioning = true
            let previous = owner
            owner = next
            if previous == .coda { stopCoda() }
            // The host may already have audio before Coda was first opened (.none).
            if next == .coda { stopReadcc() }
            transitioning = false
            return true
        }
    }

    public static let audio = AudioOwnership()
    public private(set) static var isEmbedded = false
    public static var allowsStandaloneUpdates: Bool { !isEmbedded }

    /// Process-level host policy; configure at Readcc launch before constructing Coda views.
    /// Never records consent and never alters any provider/account authorization.
    public static func configureEmbeddedHost() { isEmbedded = true }

    public static func acceptsBackgroundSession(identifier: String) -> Bool {
        identifier == BackgroundDownloadTransport.identifier
    }

    /// False means the existing application delegate must route it elsewhere / complete it.
    /// A foreign identifier never initializes Coda's download manager.
    @discardableResult
    public static func handleBackgroundSession(identifier: String, completion: @escaping () -> Void) -> Bool {
        guard acceptsBackgroundSession(identifier: identifier) else { return false }
        OfflineDownloadEvents.handleBackgroundSession(identifier: identifier, completion: completion)
        return true
    }
}
