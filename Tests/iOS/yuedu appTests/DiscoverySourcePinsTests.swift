import Foundation
import Testing
@testable import yuedu_app

@Suite("Discovery source picker pins")
@MainActor
struct DiscoverySourcePinsTests {
    private func candidate(_ name: String, id: UUID = UUID(), url: String = "https://example.test") -> DiscoverableBookSource {
        DiscoverableBookSource(id: id, name: name, url: url)
    }

    @Test("pinning immediately updates order and saves UUID preferences")
    func pinAppliesImmediately() throws {
        let suite = "DiscoverySourcePinsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let pins = DiscoverySourcePins(defaults: defaults)
        let first = candidate("甲"), second = candidate("乙")
        let sources = [first, second]
        let ids = Set(sources.map(\.id))

        pins.togglePin(second.id, availableIDs: ids)
        #expect(pins.pinnedIDs == [second.id])
        #expect(pins.ordered(sources).map(\.id) == [second.id, first.id])
        #expect(defaults.stringArray(forKey: DiscoverySourcePins.preferenceKey) == [second.id.uuidString])
        #expect(DiscoverySourcePins(defaults: defaults).pinnedIDs == [second.id])
        #expect(sources.map(\.id) == [first.id, second.id])
    }

    @Test("newest pins come first and unpin immediately restores the source order")
    func multiPinOrderAndUnpin() throws {
        let suite = "DiscoverySourcePinsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let pins = DiscoverySourcePins(defaults: defaults)
        let first = candidate("甲"), second = candidate("乙"), third = candidate("丙")
        let sources = [first, second, third]
        let ids = Set(sources.map(\.id))

        pins.togglePin(second.id, availableIDs: ids)
        #expect(pins.ordered(sources).map(\.id) == [second.id, first.id, third.id])
        pins.togglePin(third.id, availableIDs: ids)
        #expect(pins.ordered(sources).map(\.id) == [third.id, second.id, first.id])
        #expect(sources.map(\.id) == [first.id, second.id, third.id])

        pins.togglePin(third.id, availableIDs: ids)
        #expect(pins.ordered(sources).map(\.id) == [second.id, first.id, third.id])
        let restored = DiscoverySourcePins(defaults: defaults)
        #expect(!restored.isPinned(third.id))
        #expect(restored.ordered(sources).map(\.id) == [second.id, first.id, third.id])
    }

    @Test("a fresh model restores UUID pins; search and source edits preserve identity")
    func restorationSearchAndIdentity() throws {
        let suite = "DiscoverySourcePinsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let pins = DiscoverySourcePins(defaults: defaults)
        let first = candidate("甲", url: "https://a.example"), second = candidate("乙", url: "https://b.example")
        let sources = [first, second]
        pins.togglePin(second.id, availableIDs: Set(sources.map(\.id)))

        let reopenedDefaults = try #require(UserDefaults(suiteName: suite))
        let restored = DiscoverySourcePins(defaults: reopenedDefaults)
        #expect(restored.ordered(sources).map(\.id) == [second.id, first.id])
        let filtered = DiscoverySourceSearch.matching(sources, query: "a.example")
        #expect(restored.ordered(filtered).map(\.id) == [first.id])
        #expect(restored.isPinned(second.id))
        let cleared = DiscoverySourceSearch.matching(sources, query: "")
        #expect(restored.ordered(cleared).map(\.id) == [second.id, first.id])
        let renamed = candidate("新名稱", id: second.id, url: "https://edited.example")
        #expect(restored.ordered([first, renamed]).map(\.id) == [second.id, first.id])
        // The production preference contains UUIDs only, never names, URLs or headers.
        #expect(reopenedDefaults.stringArray(forKey: DiscoverySourcePins.preferenceKey) == [second.id.uuidString])
    }

    @Test("missing imports and malformed saved IDs are safe; removed sources cannot be confirmed")
    func missingSourcesAndMalformedIDs() throws {
        let suite = "DiscoverySourcePinsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = candidate("甲"), removed = candidate("舊書源"), third = candidate("丙")
        defaults.set([removed.id.uuidString, "invalid-id", third.id.uuidString, third.id.uuidString],
                     forKey: DiscoverySourcePins.preferenceKey)
        let pins = DiscoverySourcePins(defaults: defaults)
        #expect(pins.pinnedIDs == [removed.id, third.id])
        let reimported = candidate(removed.name, url: removed.url)
        #expect(!pins.isPinned(reimported.id))
        #expect(pins.ordered([first, reimported, third]).map(\.id) == [third.id, first.id, reimported.id])
        #expect(pins.ordered([]).isEmpty)
        pins.togglePin(first.id, availableIDs: [third.id])
        pins.togglePin(removed.id, availableIDs: [third.id])
        #expect(!pins.isPinned(first.id))
        #expect(pins.pinnedIDs == [removed.id, third.id])
    }
}
