import Foundation
import Testing
@testable import CodaCore

@Suite("Panel refresh coordination")
@MainActor
struct PanelRefreshTests {
    @Test func deduplicatesAndOnlyCachesSuccess() {
        let gate = PanelRefreshGate()
        let first = gate.begin(key: "account:cloud", lifetime: 300)!
        #expect(gate.begin(key: "account:cloud", lifetime: 300) == nil)
        gate.finish(first, success: false)
        let retry = gate.begin(key: "account:cloud", lifetime: 300)!
        gate.finish(retry, success: true)
        #expect(gate.begin(key: "account:cloud", lifetime: 300) == nil)
        #expect(gate.begin(key: "account:cloud", lifetime: 300, now: Date().addingTimeInterval(301)) != nil)
    }

    @Test func forcedRefreshAndAccountChangeRejectEarlierResponses() {
        let gate = PanelRefreshGate()
        let first = gate.begin(key: "a", lifetime: 300)!
        let forced = gate.begin(key: "a", lifetime: 300, force: true)!
        #expect(!gate.accepts(first))
        #expect(gate.accepts(forced))
        let otherAccount = gate.begin(key: "b", lifetime: 300)!
        gate.finish(forced, success: true)
        #expect(gate.accepts(otherAccount))
        gate.invalidate()
        #expect(!gate.accepts(otherAccount))
        #expect(gate.begin(key: "b", lifetime: 300) != nil)
    }

    @Test func statisticsRevisionRefreshesBeforeCacheExpires() {
        for lifetime: TimeInterval in [300, 1800] {
            let gate = PanelRefreshGate()
            let cached = gate.begin(key: "user:0", lifetime: lifetime)!
            gate.finish(cached, success: true)
            #expect(gate.begin(key: "user:0", lifetime: lifetime) == nil)
            let updated = gate.begin(key: "user:1", lifetime: lifetime)!
            #expect(gate.accepts(updated))
            // A newer playback report also supersedes an in-flight statistics request.
            let latest = gate.begin(key: "user:2", lifetime: lifetime)!
            #expect(!gate.accepts(updated))
            #expect(gate.accepts(latest))
        }
    }

    @Test func playbackInvalidationSurvivesAnUnmountedStatisticsPage() {
        let gate = PanelRefreshGate()
        let key = "user:\(SidebarResources.playbackRevision)"
        let cached = gate.begin(key: key, lifetime: 1800)!
        gate.finish(cached, success: true)
        // No view or notification observer exists while the report is accepted.
        SidebarResources.playbackChanged()
        let updatedKey = "user:\(SidebarResources.playbackRevision)"
        #expect(updatedKey != key)
        #expect(gate.begin(key: updatedKey, lifetime: 1800) != nil)
    }

    @Test func dailyBoundaryUsesSixAMInShanghai() throws {
        let formatter = ISO8601DateFormatter()
        let before = try #require(formatter.date(from: "2026-10-24T05:59:59+08:00"))
        let after = before.addingTimeInterval(1)
        #expect(SidebarResources.dailyPeriod(now: before) != SidebarResources.dailyPeriod(now: after))
        #expect(SidebarResources.dailyPeriod(now: after) == SidebarResources.dailyPeriod(now: after.addingTimeInterval(3600)))
    }

    @Test func cancelledRequestDoesNotBecomeFresh() async {
        let gate = PanelRefreshGate()
        let ticket = gate.begin(key: "a", lifetime: 300)!
        let task = Task { @MainActor in
            while !Task.isCancelled { await Task.yield() }
            #expect(!gate.accepts(ticket))
            gate.finish(ticket, success: true)
        }
        task.cancel()
        await task.value
        #expect(gate.begin(key: "a", lifetime: 300) != nil)
    }
}
