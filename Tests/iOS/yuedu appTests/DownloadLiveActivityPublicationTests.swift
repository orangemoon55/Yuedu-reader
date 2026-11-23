import Foundation
import Testing
@testable import yuedu_app

@Suite("Download Live Activity publication is disabled")
struct DownloadLiveActivityPublicationTests {
    @Test("No download state may publish, including the reported 48/129 progress",
          arguments: [BookOfflineDownloadState.none, .downloading, .paused, .available, .partial, .failed])
    func allDownloadStatesNeverPublish(_ downloadState: BookOfflineDownloadState) {
        var book = makeBook()
        book.offlineDownloadState = downloadState
        book.offlineDownloadTask?.setPaused(downloadState == .paused)
        let originalTask = book.offlineDownloadTask
        let payload = DownloadLiveActivityController.contentState(for: [book])
        #expect(!DownloadLiveActivityController.shouldPublish(payload))
        #expect(book.offlineDownloadTask == originalTask)
        #expect(book.offlineDownloadTask?.completedChapterCount == 48)
        #expect(book.offlineDownloadTask?.totalChapterCount == 129)
    }

    @Test("An empty shelf or nil payload never publishes")
    func nilStateNeverPublishes() {
        #expect(!DownloadLiveActivityController.shouldPublish(nil))
        #expect(!DownloadLiveActivityController.shouldPublish(
            DownloadLiveActivityController.contentState(for: [])))
    }

    @Test("Only downloading and paused tasks are payload candidates",
          arguments: [BookOfflineDownloadState.none, .downloading, .paused, .available, .partial, .failed])
    func stateFilteringRemainsPure(_ downloadState: BookOfflineDownloadState) {
        var book = makeBook()
        book.offlineDownloadState = downloadState
        let eligible = downloadState == .downloading || downloadState == .paused
        #expect(DownloadLiveActivityController.isActiveDownload(book) == eligible)
        #expect((DownloadLiveActivityController.contentState(for: [book]) != nil) == eligible)
        book.offlineDownloadTask = BookOfflineDownloadTask(requestedIndices: [])
        #expect(!DownloadLiveActivityController.isActiveDownload(book))
        #expect(DownloadLiveActivityController.contentState(for: [book]) == nil)
    }

    @MainActor
    @Test("Cleanup ends all supplied old download activities, not just the first")
    func cleanupEndsEveryExistingDownloadActivity() async {
        var ended: [Int] = []
        let controller = DownloadLiveActivityController(existingActivities: {
            (0..<3).map { id in
                .init(endImmediately: { ended.append(id) })
            }
        })
        await controller.cleanupExistingActivities()
        #expect(ended == [0, 1, 2])
    }

    @MainActor
    @Test("Cleanup enumerates again after relaunch or foreground, including empty lists")
    func cleanupReenumeratesActivitiesAndHandlesEmptyLists() async {
        var ids: [Int] = []
        var ended: [Int] = []
        var enumerations = 0
        let controller = DownloadLiveActivityController(existingActivities: {
            enumerations += 1
            return ids.map { id in
                .init(endImmediately: { ended.append(id) })
            }
        })
        await controller.cleanupExistingActivities()
        #expect(ended.isEmpty)
        ids = [7, 8]
        await controller.cleanupExistingActivities()
        ids = [9]
        await controller.cleanupExistingActivities()
        #expect(enumerations == 3)
        #expect(ended == [7, 8, 9])
    }

    private func makeBook() -> ReadingBook {
        var book = ReadingBook(title: "离线缓存", author: "作者", source: "https://example.com",
                               contentFilename: "download-policy-test.txt")
        var task = BookOfflineDownloadTask(requestedIndices: Set(0..<129))
        for index in 0..<48 { task.markCompleted(index) }
        book.offlineDownloadTask = task
        book.offlineDownloadState = .downloading
        return book
    }
}
