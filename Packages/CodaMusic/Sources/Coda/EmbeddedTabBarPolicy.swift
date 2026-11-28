import Foundation

/// Value-only host chrome contract; no account, playback or reading state crosses it.
public struct ReadccTabBarMetrics: Equatable, Sendable {
    public let iconSize: CGFloat
    public let labelLineHeight: CGFloat
    public let showsLabels: Bool
    public let accessibilityText: Bool
    public init(iconSize: CGFloat = 24, labelLineHeight: CGFloat = 15,
                showsLabels: Bool = true, accessibilityText: Bool = false) {
        self.iconSize = iconSize.isFinite ? max(1, min(80, iconSize)) : 24
        self.labelLineHeight = labelLineHeight.isFinite ? max(0, labelLineHeight) : 15
        self.showsLabels = showsLabels
        self.accessibilityText = accessibilityText
    }
    public var contentHeight: CGFloat {
        let text = showsLabels ? labelLineHeight * (accessibilityText ? 2 : 1) + 2 : 0
        return max(52, iconSize + text + 4)
    }
    public var height: CGFloat { contentHeight + 8 }
}

public enum CodaEmbeddedUIPolicy {
    public static func usesNativePhoneTabs(embedded: Bool, nativeAvailable: Bool) -> Bool {
        nativeAvailable && !embedded
    }
    public static func showsLikedRecommendations(loggedIn: Bool, showLoginRequired: Bool) -> Bool {
        loggedIn || showLoginRequired
    }
    public static func canReturnToBookshelf(embedded: Bool, recommendation: Bool, hasAction: Bool) -> Bool {
        embedded && recommendation && hasAction
    }
}

/// One contact owns tap, horizontal slide and hold. No Button/gesture race and
/// no suppression flag can survive the end or cancellation of a contact.
struct CodaTabBarInteraction: Equatable {
    enum Outcome: Equatable { case none, tap(Int), drag(Int) }
    private(set) var startIndex: Int?
    private(set) var isDragging = false
    private(set) var holdRecognized = false
    private(set) var moved = false
    mutating func begin(index: Int) { self = Self(); startIndex = index }
    mutating func move(horizontal: CGFloat, vertical: CGFloat) {
        guard startIndex != nil, !holdRecognized else { return }
        if (horizontal * horizontal + vertical * vertical).squareRoot() >= 8 { moved = true }
        if moved && abs(horizontal) > abs(vertical) { isDragging = true }
    }
    mutating func recognizeHold(allowed: Bool) -> Bool {
        guard allowed, startIndex != nil, !moved, !holdRecognized else { return false }
        holdRecognized = true
        return true
    }
    mutating func finish(index: Int, inside: Bool) -> Outcome {
        defer { cancel() }
        guard let startIndex, inside, !holdRecognized else { return .none }
        if isDragging { return .drag(index) }
        return !moved && index == startIndex ? .tap(index) : .none
    }
    mutating func cancel() { self = Self() }
}
