import Foundation
import Testing
@testable import yuedu_app

@Suite("Source discovery selection")
struct SourceDiscoverySelectionTests {
    private func candidate(_ name: String, _ url: String) -> DiscoverableBookSource {
        DiscoverableBookSource(id: UUID(), name: name, url: url)
    }

    @Test("remembers a matching enabled discovery source")
    func keepsSavedSource() {
        let first = candidate("甲", "https://a.example")
        let second = candidate("乙", "https://b.example")
        #expect(SourceDiscoverySelection.preferredSource(in: [first, second], savedURL: second.url)?.id == second.id)
    }

    @Test("falls back when the remembered source is no longer available")
    func fallsBackToFirstAvailableSource() {
        let first = candidate("甲", "https://a.example")
        #expect(SourceDiscoverySelection.preferredSource(in: [first], savedURL: "https://deleted.example")?.id == first.id)
        #expect(SourceDiscoverySelection.preferredSource(in: [], savedURL: nil) == nil)
    }
}
