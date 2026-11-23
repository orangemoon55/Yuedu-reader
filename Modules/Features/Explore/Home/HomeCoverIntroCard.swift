import SwiftUI

/// A full-width card with equal cover and introduction columns.
struct HomeCoverIntroCard: View {
    let content: HomeCardContent
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var scaledHeight = DSLayout.homeCoverIntroMinimumHeight

    var body: some View {
        HomeCoverIntroLayout(minimumHeight: min(scaledHeight, DSLayout.homeCoverIntroMaximumHeight)) {
            GeometryReader { geometry in
                HomeCoverArtwork(cover: content.cover, title: content.title, author: content.author, size: geometry.size)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text(content.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if !content.author.isEmpty {
                    Text(content.author)
                        .font(.subheadline)
                        .foregroundStyle(DSColor.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let category = content.category, !category.isEmpty {
                    Text(category).font(.caption).foregroundStyle(DSColor.textSecondary).lineLimit(1)
                }
                Text(introduction)
                    .font(.subheadline)
                    .foregroundStyle(DSColor.textSecondary)
                    .lineSpacing(3)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 5 : 9)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .clipped()
            }
            .padding(DSSpacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                .strokeBorder(DSColor.textPrimary.opacity(0.06))
        }
    }

    private var introduction: String {
        guard let blurb = content.blurb?.trimmingCharacters(in: .whitespacesAndNewlines), !blurb.isEmpty else {
            return localized("暫無簡介")
        }
        return blurb
    }
}

/// Half-width cover and text laid out in one pass, including in a native Form.
struct HomeCoverIntroLayout: Layout {
    let minimumHeight: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(0, proposal.width ?? DSLayout.homeContinueCardWidth)
        return CGSize(width: width, height: max(minimumHeight, width / 2 / DSLayout.discoverCoverAspectRatio))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let size = ProposedViewSize(width: bounds.width / 2, height: bounds.height)
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: size)
        subviews[1].place(at: CGPoint(x: bounds.midX, y: bounds.minY), anchor: .topLeading, proposal: size)
    }
}

#Preview {
    HomeCoverIntroCard(content: HomeCardContent(sample: "戰爭與和平", author: "列夫·托爾斯泰", kind: .text,
                                               cover: nil, blurb: "在時代的洪流中，幾個家族的命運交錯。由戰爭、生活與愛情展開的長篇故事。"))
        .padding()
}
