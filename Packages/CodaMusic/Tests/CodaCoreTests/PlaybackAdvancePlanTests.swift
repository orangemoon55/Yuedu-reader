import Foundation
import Testing
@testable import CodaCore

private func advanceTrack(_ id: Int) throws -> Track {
    try JSONDecoder().decode(Track.self, from: JSONSerialization.data(withJSONObject: ["id": id, "name": "Track \(id)", "dt": 3000]))
}

private func feed(hasMore: Bool) -> QishuiFeedState {
    QishuiFeedState(kind: .scene(QishuiListeningScene(title: "Scene", mode: "scene", sceneID: nil)),
                    startedAt: 0, hasMore: hasMore)
}

private func nextStep(count: Int = 3, at index: Int = 0, playNext: Bool = false, fm: Bool = false,
                      offline: Bool = false, repeatMode: RepeatMode = .off,
                      qishui: QishuiFeedState? = nil, loading: Bool = false) -> PlaybackAdvancePlan.Next {
    PlaybackAdvancePlan.next(queueCount: count, currentIndex: index, hasPlayNext: playNext, isFM: fm,
                             offlineHasCandidates: offline, repeatMode: repeatMode,
                             qishuiFeed: qishui, isLoadingQishuiFeed: loading)
}

@Suite("Next and previous track decisions")
struct PlaybackAdvancePlanTests {
    @Test func sourcesAreCheckedInPriorityOrder() {
        #expect(nextStep(playNext: true, fm: true, offline: true) == .offline)
        #expect(nextStep(playNext: true, fm: true) == .personalFM)
        #expect(nextStep(playNext: true) == .playNext)
        #expect(nextStep(at: 0) == .queue(index: 1))
        #expect(nextStep(count: 0) == .idle)
    }

    @Test func queueEndWrapsOnlyWithRepeatAll() {
        #expect(nextStep(at: 2) == .endOfQueue)
        #expect(nextStep(at: 2, repeatMode: .one) == .endOfQueue)
        #expect(nextStep(at: 2, repeatMode: .all) == .queue(index: 0))
    }

    @Test func qishuiStreamLoadsMoreInsteadOfWrapping() {
        let more = feed(hasMore: true)
        #expect(nextStep(at: 2, repeatMode: .all, qishui: more) == .loadMoreQishui(more))
        #expect(nextStep(at: 2, qishui: more, loading: true) == .waitForQishui)
        #expect(nextStep(at: 2, repeatMode: .all, qishui: feed(hasMore: false)) == .endOfQueue)
        #expect(nextStep(at: 0, qishui: more) == .queue(index: 1))
    }

    @Test func previousAlwaysChangesTrackAndWrapsOnlyWhenUseful() {
        #expect(PlaybackAdvancePlan.previousIndex(queueCount: 3, currentIndex: 2, isFM: false, repeatMode: .off) == 1)
        #expect(PlaybackAdvancePlan.previousIndex(queueCount: 3, currentIndex: 0, isFM: false, repeatMode: .off) == nil)
        #expect(PlaybackAdvancePlan.previousIndex(queueCount: 3, currentIndex: 0, isFM: false, repeatMode: .all) == 2)
        #expect(PlaybackAdvancePlan.previousIndex(queueCount: 1, currentIndex: 0, isFM: false, repeatMode: .all) == nil)
        #expect(PlaybackAdvancePlan.previousIndex(queueCount: 3, currentIndex: 2, isFM: true, repeatMode: .all) == nil)
        #expect(PlaybackAdvancePlan.previousIndex(queueCount: 0, currentIndex: 0, isFM: false, repeatMode: .all) == nil)
    }

    @Test func qishuiExclusionsKeepTheRecentWindow() throws {
        let queue = try (0..<250).map { try advanceTrack($0) }
        let excluded = try PlaybackAdvancePlan.qishuiExclusions(
            queue: queue, playNext: [advanceTrack(900)], current: advanceTrack(901))
        #expect(excluded.count == 202)
        #expect(excluded.first?.id == 50)
        #expect(excluded.suffix(2).map(\.id) == [900, 901])
    }

    @MainActor @Test func fmRefillRetriesThenReportsFailure() async throws {
        var calls = 0
        let failed = await PersonalFMRefill.load(fetch: { calls += 1; return [] },
                                                 retryDelay: .zero, isCurrent: { true })
        #expect(failed == .failed)
        #expect(calls == 3)

        calls = 0
        let track = try advanceTrack(7)
        let loaded = await PersonalFMRefill.load(fetch: {
            calls += 1
            if calls < 2 { throw URLError(.timedOut) }
            return [track]
        }, retryDelay: .zero, isCurrent: { true })
        #expect(loaded == .loaded([track]))
        #expect(calls == 2)

        let superseded = await PersonalFMRefill.load(fetch: { [track] }, retryDelay: .zero, isCurrent: { false })
        #expect(superseded == .superseded)
    }
}
