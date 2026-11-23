import SwiftUI

/// Scroll requests affect only the open TOC, never the current reading chapter.
enum ReaderTOCEdge: Hashable {
    case first
    case latest

    func target(in chapters: [BookChapter]) -> Int? {
        switch self {
        case .first: ReaderTOCScrollTarget.first(in: chapters)
        case .latest: ReaderTOCScrollTarget.latest(in: chapters)
        }
    }

    /// The same readable-edge rule for image chapters. This only returns an index;
    /// the chapter array, persisted order and live reader position are never changed.
    func target<Item>(in items: [Item], index: (Item) -> Int, title: (Item) -> String) -> Int? {
        let readable: Item?
        switch self {
        case .first: readable = items.first { !ReaderTOCScrollTarget.isVolumeHeading(title($0)) } ?? items.first
        case .latest: readable = items.last { !ReaderTOCScrollTarget.isVolumeHeading(title($0)) } ?? items.last
        }
        return readable.map(index)
    }

    func anchor(verticalColumns: Bool) -> UnitPoint {
        if verticalColumns { return self == .first ? .trailing : .leading }
        return self == .first ? .top : .bottom
    }
}

struct ReaderTOCEdgeRequest: Equatable {
    let destination: ReaderTOCEdge
    let id = UUID()
}

/// Use the final readable row's actual frame, not List onAppear (which prefetches
/// rows). The last row must intersect the viewport and expose its final edge.
enum ReaderTOCEdgeVisibility {
    static func isAtLatest(row: CGRect?, viewport: CGRect, verticalColumns: Bool) -> Bool {
        guard let row, !row.isEmpty, !viewport.isEmpty,
              [row.minX, row.maxX, row.minY, row.maxY,
               viewport.minX, viewport.maxX, viewport.minY, viewport.maxY].allSatisfy(\.isFinite)
        else { return false }
        let tolerance: CGFloat = 1
        if verticalColumns {
            // Traditional vertical columns flow right-to-left; newest is on the left.
            return row.maxX > viewport.minX && row.minX < viewport.maxX
                && row.minX >= viewport.minX - tolerance
                && row.maxY > viewport.minY && row.minY < viewport.maxY
        }
        return row.maxY > viewport.minY && row.minY < viewport.maxY
            && row.maxY <= viewport.maxY + tolerance
            && row.maxX > viewport.minX && row.minX < viewport.maxX
    }
}

struct ReaderTOCEdgeFramesKey: PreferenceKey {
    static let defaultValue: [ReaderTOCEdge: CGRect] = [:]
    static func reduce(value: inout [ReaderTOCEdge: CGRect], nextValue: () -> [ReaderTOCEdge: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

extension View {
    func reportTOCEdges(for chapter: BookChapter, first: Int?, latest: Int?) -> some View {
        reportTOCEdges(index: chapter.index, first: first, latest: latest)
    }

    /// Shared geometry reporting for both text chapters and fixed-page chapter items.
    func reportTOCEdges(index: Int, first: Int?, latest: Int?) -> some View {
        background {
            if index == first || index == latest {
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .global)
                    let pairs: [(ReaderTOCEdge, CGRect)] =
                        (index == first ? [(.first, frame)] : [])
                        + (index == latest ? [(.latest, frame)] : [])
                    Color.clear.preference(key: ReaderTOCEdgeFramesKey.self,
                                           value: Dictionary(uniqueKeysWithValues: pairs))
                }
            }
        }
    }
}
