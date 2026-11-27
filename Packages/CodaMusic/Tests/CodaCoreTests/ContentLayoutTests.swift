#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import CodaCore

@Suite("Shared content layout")
@MainActor
struct ContentLayoutTests {
    @Test(arguments: ["一张专辑", "很长的歌单名称，用来确认两行标题和副标题不会被横向栏目的固定高度截断"])
    func coverCardFitsItsShelf(title: String) {
        let card = CoverCard(coverURL: nil, title: title,
                             subtitle: "歌手与专辑的辅助信息", onOpen: {})
        let host = NSHostingView(rootView: card)
        let size = host.fittingSize
        #expect(size.width == Theme.Layout.cardSize)
        #expect(size.height > Theme.Layout.cardSize)
        #expect(size.height <= Theme.Layout.coverShelfHeight)
    }

    @Test func errorMessageWrapsWithinANarrowContentColumn() {
        let host = NSHostingView(rootView:
            ErrorStateView(message: String(repeating: "暂时无法连接音乐服务，请稍后重试。", count: 5), retry: {})
                .frame(width: 320))
        let size = host.fittingSize
        #expect(size.width == 320)
        #expect(size.height.isFinite)
        #expect(size.height > 160)
    }
}
#endif
