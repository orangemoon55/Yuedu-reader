import UIKit

/// XCTestCase inherits NSObject's accessibilityElements selector; a concrete helper
/// namespace avoids both that selector and the suite class named yuedu_appTests.
@MainActor
enum HomeRankAX {
    static func elements(in object: NSObject) -> [NSObject] {
        if object.isAccessibilityElement { return [object] }
        let children = (object.accessibilityElements as? [NSObject]) ?? (object as? UIView)?.subviews ?? []
        return children.flatMap { elements(in: $0) }
    }
}
