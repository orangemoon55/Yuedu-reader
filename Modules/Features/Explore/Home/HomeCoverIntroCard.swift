import SwiftUI

/// A full-width card with equal cover and introduction columns.
struct HomeCoverIntroCard: View {
    let content: HomeCardContent
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var scaledHeight: CGFloat = 264
    @State private var width: CGFloat = 0

    var body: some View {
        let half = max(1, width / 2)
        let height = max(min(scaledHeight, 620), half / DSLayout.discoverCoverAspectRatio)
        HStack(alignment: .top, spacing: 0) {
            HomeCoverArtwork(cover: content.cover, title: content.title, author: content.author,
                             size: CGSize(width: half, height: height))
                .frame(width: half, height: height)
                .clipped()
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
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
            .padding(14)
            .frame(width: half, height: height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                .strokeBorder(DSColor.textPrimary.opacity(0.06))
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private var introduction: String {
        guard let blurb = content.blurb?.trimmingCharacters(in: .whitespacesAndNewlines), !blurb.isEmpty else {
            return localized("暫無簡介")
        }
        return blurb
    }
}

#Preview {
    HomeCoverIntroCard(content: HomeCardContent(sample: "戰爭與和平", author: "列夫·托爾斯泰", kind: .text,
                                               cover: nil, blurb: "在時代的洪流中，幾個家族的命運交錯。由戰爭、生活與愛情展開的長篇故事。"))
        .padding()
}
