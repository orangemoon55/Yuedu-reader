import SwiftUI

enum BookshelfBookContextAction {
    case open
    case showDetail
    case searchCover
    case toggleFatten
    case delete
}

struct BookshelfBookContextMenu: View {
    let book: ReadingBook
    var isFattened = false
    let onOpen: () -> Void
    let onShowDetail: () -> Void
    let onSearchCover: () -> Void
    let onToggleFatten: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Label(localized("打開"), systemImage: "book")
        }
        Button(action: onShowDetail) {
            Label(localized("打開書籍詳情頁"), systemImage: "info.circle")
        }
        Button(action: onSearchCover) {
            Label(localized("搜索網絡封面"), systemImage: "photo.on.rectangle.angled")
        }
        Button(action: onToggleFatten) {
            Label(
                localized(isFattened ? "移出養肥" : "加入養肥"),
                systemImage: isFattened ? "leaf.fill" : "leaf"
            )
        }
        Button(role: .destructive, action: onDelete) {
            Label(localized("刪除書籍"), systemImage: "trash")
        }
    }
}
