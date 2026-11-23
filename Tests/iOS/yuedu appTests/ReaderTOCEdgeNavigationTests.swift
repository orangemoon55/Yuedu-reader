import SwiftUI
import Testing
@testable import yuedu_app

@Suite("Reader TOC edge navigation")
struct ReaderTOCEdgeNavigationTests {
    @Test("first and latest skip volume headings but never change order or chapter identity")
    func targets() {
        let chapters = [BookChapter(index: 4, title: "第一卷", content: ""),
                        BookChapter(index: 12, title: "第一章 初入", content: ""),
                        BookChapter(index: 85, title: "第二章 相逢", content: ""),
                        BookChapter(index: 105, title: "第二卷", content: "")]
        #expect(ReaderTOCEdge.first.target(in: chapters) == 12)
        #expect(ReaderTOCEdge.latest.target(in: chapters) == 85)
        #expect(chapters.map(\.index) == [4, 12, 85, 105])
        #expect(ReaderTOCEdge.first.target(in: []) == nil)
        #expect(ReaderTOCEdge.latest.target(in: []) == nil)
        #expect(ReaderTOCEdge.first.target(in: [chapters[0]]) == 4)
        #expect(ReaderTOCEdge.latest.target(in: [chapters[1]]) == 12)
    }

    @Test("bottom means the latest row is actually visible, not prefetched or partially clipped")
    func viewport() {
        let view = CGRect(x: 0, y: 100, width: 390, height: 600)
        func bottom(_ y: CGFloat, _ height: CGFloat = 50) -> Bool {
            ReaderTOCEdgeVisibility.isAtLatest(row: CGRect(x: 0, y: y, width: 390, height: height),
                                              viewport: view, verticalColumns: false)
        }
        #expect(bottom(650))
        #expect(bottom(640))
        #expect(bottom(300)) // short list, everything is already visible
        #expect(!bottom(651.5))
        #expect(!bottom(1200))
        #expect(!bottom(-60))
        #expect(!ReaderTOCEdgeVisibility.isAtLatest(row: nil, viewport: view, verticalColumns: false))
        #expect(!ReaderTOCEdgeVisibility.isAtLatest(row: .zero, viewport: view, verticalColumns: false))
        #expect(!ReaderTOCEdgeVisibility.isAtLatest(row: view, viewport: .zero, verticalColumns: false))
        #expect(!ReaderTOCEdgeVisibility.isAtLatest(row: CGRect(x: 0, y: CGFloat.infinity, width: 1, height: 1),
                                                    viewport: view, verticalColumns: false))
    }

    @Test("vertical columns use the left edge for latest and right edge for first")
    func vertical() {
        let view = CGRect(x: 10, y: 100, width: 360, height: 550)
        #expect(ReaderTOCEdgeVisibility.isAtLatest(row: CGRect(x: 10, y: 120, width: 46, height: 500),
                                                  viewport: view, verticalColumns: true))
        #expect(!ReaderTOCEdgeVisibility.isAtLatest(row: CGRect(x: -25, y: 120, width: 46, height: 500),
                                                   viewport: view, verticalColumns: true))
        #expect(!ReaderTOCEdgeVisibility.isAtLatest(row: CGRect(x: 500, y: 120, width: 46, height: 500),
                                                   viewport: view, verticalColumns: true))
        #expect(ReaderTOCEdge.first.anchor(verticalColumns: true) == .trailing)
        #expect(ReaderTOCEdge.latest.anchor(verticalColumns: true) == .leading)
        #expect(ReaderTOCEdge.first.anchor(verticalColumns: false) == .top)
        #expect(ReaderTOCEdge.latest.anchor(verticalColumns: false) == .bottom)
    }

    @Test("repeated edge actions always issue a new request")
    func requests() {
        #expect(ReaderTOCEdgeRequest(destination: .first) != ReaderTOCEdgeRequest(destination: .first))
        #expect(ReaderTOCEdgeRequest(destination: .latest).destination == .latest)
    }
}
