import CoreGraphics
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import yuedu_app

@Suite("Dynamic ring shelf sectors and chapter context")
struct BookshelfRingTests {
    private let center = CGPoint(x: 200, y: 200)

    @Test("One through nine books each own one sector through multi-turn rotation")
    func rotatedSectors() {
        for count in 1...9 {
            let step = CGFloat(360) / CGFloat(count)
            for rotation: CGFloat in [-765, -90, 0, 67, 405] {
                for slot in 0..<count {
                    let point = point(degrees: CGFloat(slot) * step + rotation - 90)
                    #expect(BookshelfRingGeometry.slot(at: point, center: center, diameter: 400,
                                                      rotation: rotation, count: count) == slot)
                }
            }
        }
    }

    @Test("Dynamic sectors preserve hit locations across shelf sizes")
    func scaledGeometry() {
        for count in 1...9 {
            for diameter: CGFloat in [240, 320, 440] {
                let center = CGPoint(x: diameter / 2 + 25, y: diameter / 2 + 50)
                let right = CGPoint(x: center.x + diameter * 0.3, y: center.y)
                #expect(BookshelfRingGeometry.slot(at: right, center: center, diameter: diameter,
                                                  rotation: 90, count: count) == 0)
            }
        }
        #expect(!BookshelfRingChapterContext.dailyMessage(for: " \n ").isEmpty)
    }

    @Test("Dynamic seams wrap, small shelves have no empty sectors, and the hole stays inert")
    func dynamicBoundaries() {
        for count in 1...9 {
            let halfStep = CGFloat(180) / CGFloat(count)
            #expect(hit(degrees: -90 + halfStep - 0.01, count: count) == 0)
            #expect(hit(degrees: -90 + halfStep + 0.01, count: count) == 1 % count)
            #expect(hit(degrees: -90 - halfStep - 0.01, count: count) == count - 1)
            #expect(hit(degrees: -90 - halfStep + 0.01, count: count) == 0)
            #expect(hit(degrees: -90, count: count, radius: 10) == nil)
            #expect(hit(degrees: -90, count: count, radius: 60) == 0)
            #expect(hit(degrees: -90, count: count, radius: 190) == nil)
        }
        #expect(hit(degrees: -90, count: 0) == nil)
        #expect(hit(degrees: -90, count: -1) == nil)
        #expect(hit(degrees: 30, count: 3) == 1)
        #expect(hit(degrees: 150, count: 3) == 2)
        #expect(BookshelfRingGeometry.slot(at: center, center: center, diameter: .nan,
                                          rotation: 0, count: 9) == nil)
        #expect(BookshelfRingGeometry.slot(at: point(degrees: -90), center: center, diameter: 400,
                                          rotation: .infinity, count: 9) == nil)
    }

    @Test("Snap targets use the actual sector count and the closest equivalent revolution")
    func dynamicSnapTargets() {
        for count in 1...9 {
            let step = CGFloat(360) / CGFloat(count)
            for slot in 0..<count {
                for angle: CGFloat in [-1485, -765, -15, 0, 405, 1080] {
                    let target = BookshelfRingGeometry.target(slot: slot, near: angle, count: count)
                    #expect(abs(target - angle) <= 180.0001)
                    #expect(BookshelfRingGeometry.nearestSlot(to: target, count: count) == slot)
                    #expect(BookshelfRingGeometry.nearestSlot(to: target + step * 0.49, count: count) == slot)
                    #expect(BookshelfRingGeometry.nearestSlot(to: target - step * 0.49, count: count) == slot)
                    let front = point(degrees: -90)
                    #expect(BookshelfRingGeometry.slot(at: front, center: center, diameter: 400,
                                                      rotation: target, count: count) == slot)
                }
            }
        }
        #expect(BookshelfRingGeometry.nearestSlot(to: 90, count: 0) == 0)
        #expect(BookshelfRingGeometry.target(slot: 0, near: 90, count: 0) == 0)
    }

    @Test("Overflow books never add a tenth sector or a more-books sector")
    func overflowLimit() {
        for count in [9, 10, 12, 30] {
            for slot in 0..<9 {
                #expect(hit(degrees: CGFloat(slot) * 40 - 90, count: count) == slot)
                let target = BookshelfRingGeometry.target(slot: slot, near: 0, count: count)
                #expect(BookshelfRingGeometry.nearestSlot(to: target, count: count) == slot)
            }
        }
    }

    @Test("Text resume titles strip HTML and newest titles come from shelf summaries")
    func textChapterTitles() {
        var book = ReadingBook(title: "三體", contentFilename: "book.txt")
        book.isOnline = true
        book.latestChapterTitle = " <b>第十章</b>\n 終點 "
        let context = BookshelfRingChapterContext(book: book, chapters: chapters,
                                                  textPosition: .chapterStart(2))
        #expect(context.currentTitle == "第二章 星光")
        #expect(context.latestTitle == "第十章 終點")
        #expect(!context.isUnread)
        #expect(context.readingPrompt.contains(context.currentTitle))
        #expect(context.currentChapterLine.contains(context.currentTitle))
        #expect(context.latestChapterLine.contains("第十章 終點"))
    }

    @Test("Media use the reader's own position instead of text spine position")
    func mediaChapterSources() {
        for kind: BookPipelineKind in [.manga, .fixedPage, .audio, .video] {
            var book = ReadingBook(title: "媒體", contentFilename: "")
            book.contentPipelineKind = kind
            book.mangaChapterIndex = 2
            book.audioChapterIndex = 2
            let context = BookshelfRingChapterContext(book: book, chapters: chapters,
                                                      textPosition: .chapterStart(1))
            #expect(context.currentTitle == "第二章 星光")
            #expect(!context.isUnread)
        }
    }
    @Test("Unread and stale positions skip volume headings and fall back to numbered chapters")
    func unreadAndMissingTOC() {
        let book = ReadingBook(title: "三體", contentFilename: "book.txt")
        let unread = BookshelfRingChapterContext(book: book, chapters: chapters, textPosition: nil)
        #expect(unread.currentTitle == "第一章")
        #expect(unread.isUnread)
        let stale = BookshelfRingChapterContext(book: book, chapters: chapters,
                                                textPosition: .chapterStart(99))
        #expect(stale.currentTitle == "第二章 星光")
        let unknown = BookshelfRingChapterContext(book: book, chapters: [],
                                                  textPosition: .chapterStart(3))
        #expect(unknown.currentTitle.contains("4"))
        #expect(unknown.latestTitle == nil)
        #expect(!unknown.latestChapterLine.isEmpty)
        #expect(BookshelfRingChapterContext.dailyMessage(for: "三體").contains("三體"))
    }

    @Test("Ring callbacks carry the drawn bitmap and geometry updated after rotation")
    @MainActor
    func realCoverSource() throws {
        let sources = BookshelfRingCoverSources()
        let book = ReadingBook(title: "三體", contentFilename: "book.txt")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 84)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 60, height: 84))
        }
        let box = sources.box(for: book.id)
        box.drawnCover = .bitmap(image, .bookCover(filename: "ring-test.jpg"))
        box.frame = CGRect(x: 10, y: 20, width: 60, height: 84)
        #expect(sources.tappedCover(for: book.id).geometry?.frame == box.frame)
        box.frame = CGRect(x: 180, y: 160, width: 60, height: 84)
        var opened: (ReadingBook, BookshelfTappedCover)?
        sources.open(book) { opened = ($0, $1) }
        let (openedBook, tapped) = try #require(opened)
        #expect(openedBook.id == book.id)
        #expect(tapped.geometry?.frame == box.frame)
        let snapshot = try #require(BookshelfCoverStyle.snapshot(
            for: book, drawn: tapped.drawnCover, catalogImage: tapped.catalogImage, colorScheme: .light
        ))
        #expect(snapshot.cgImage != nil)
        let source = ReaderTransitionSource(bookID: book.id, frameProvider: { box.frame },
                                            snapshot: snapshot)
        #expect(source.canAnimateCardClose)
        #expect(BookshelfCoverStyle.snapshot(for: book, drawn: nil, colorScheme: .light) == nil)
    }

    private var chapters: [OnlineChapterRef] {
        [OnlineChapterRef(index: 0, title: "卷一", url: "", isVolume: true),
         OnlineChapterRef(index: 1, title: "第一章", url: "https://c.test/1"),
         OnlineChapterRef(index: 2, title: "<b>第二章</b>\n 星光", url: "https://c.test/2")]
    }

    private func point(degrees: CGFloat, radius: CGFloat = 130) -> CGPoint {
        CGPoint(x: center.x + cos(degrees * .pi / 180) * radius,
                y: center.y + sin(degrees * .pi / 180) * radius)
    }

    private func hit(degrees: CGFloat, count: Int = 9, radius: CGFloat = 130) -> Int? {
        BookshelfRingGeometry.slot(at: point(degrees: degrees, radius: radius), center: center,
                                   diameter: 400, rotation: 0, count: count)
    }
}
