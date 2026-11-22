import SwiftUI

struct MangaCanvasLayout {
    static let sideMargin: CGFloat = 4
    static func horizontalInset(isManga: Bool) -> CGFloat { isManga ? sideMargin : 0 }
}

extension View {
    func mangaCanvasMargins(isManga: Bool) -> some View {
        padding(.horizontal, MangaCanvasLayout.horizontalInset(isManga: isManga))
    }
}
