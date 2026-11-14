import SwiftUI

/// The online book's cover, source and actions share one dark header.
struct OnlineBookSourceHero<Cover: View>: View {
    let cover: Cover
    let title: String
    let author: String
    let meta: String
    let sourceName: String
    let summary: String
    let primary: BookDetailAction
    let secondary: BookDetailAction
    var authorActions: [BookDetailAuthorAction] = []
    var sourceGestures: BookDetailSourceGestures?
    var links: [BookDetailLink] = []
    var seriesFan: SeriesFan?
    let onChooseSource: () -> Void

    private var background: Color { Color(red: 53 / 255, green: 65 / 255, blue: 75 / 255) }
    private var quiet: Color { Color(red: 168 / 255, green: 187 / 255, blue: 202 / 255) }
    private var coverSize: CGSize { CGSize(width: 196, height: 294) }

    var body: some View {
        VStack(spacing: 0) {
            cover
                .frame(width: coverSize.width, height: coverSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
                .background(alignment: .bottom) {
                    if let seriesFan { SeriesCoverFan(fan: seriesFan, size: coverSize) }
                }
                .accessibilityHidden(true)
                .padding(.bottom, 24)
            titleBlock
            sourceCard.padding(.top, 20)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            GeometryReader { proxy in
                background
                    .frame(height: proxy.size.height + 400)
                    .offset(y: -400)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var titleBlock: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .sourceGesture(tap: sourceGestures?.tapName,
                               longPress: sourceGestures?.longPressName,
                               longPressName: localized("長按書名"))
            if let gestures = sourceGestures, authorActions.isEmpty {
                Text(author)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(minHeight: 44)
                    .sourceGesture(tap: gestures.tapAuthor,
                                   longPress: gestures.longPressAuthor,
                                   longPressName: localized("長按作者"))
            } else if authorActions.isEmpty {
                Text(author)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(minHeight: 44)
            } else {
                ForEach(authorActions) { action in
                    Button(action: action.action) {
                        HStack(spacing: 5) {
                            Text(action.name)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        }
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let gestures = sourceGestures, !gestures.labels.isEmpty {
                WrappingFlowLayout(spacing: 8, alignment: .center) {
                    ForEach(gestures.labels, id: \.self) { label in
                        Text(label)
                            .font(.footnote)
                            .foregroundStyle(quiet)
                            .sourceGesture(tap: { gestures.tapLabel(label) },
                                           longPress: { gestures.longPressLabel(label) },
                                           longPressName: localized("長按標籤"))
                    }
                }
            } else if !links.isEmpty {
                WrappingFlowLayout(spacing: 10, alignment: .center) {
                    ForEach(links) { link in
                        Button(action: link.action) {
                            Text(link.title).font(.footnote).foregroundStyle(quiet)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(link.hint ?? localized("顯示這個分類的作品"))
                    }
                }
            } else if !meta.isEmpty {
                Text(meta).font(.footnote).foregroundStyle(quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onChooseSource) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(sourceName).font(.headline).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    Text(summary).font(.footnote).foregroundStyle(quiet)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(localized("切換來源配置"))
            HStack(spacing: 12) {
                shelfButton
                actionButton(primary, isPrimary: true)
            }
        }
        .padding(16)
        .background(Color.black.opacity(0.17), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var shelfButton: some View {
        if let confirmation = secondary.removalConfirmation {
            actionButton(secondary, isPrimary: false)
                .removeFromShelfConfirmation(isPresented: confirmation.isPresented,
                                             onConfirm: confirmation.onConfirm)
        } else {
            actionButton(secondary, isPrimary: false)
        }
    }

    private func actionButton(_ action: BookDetailAction, isPrimary: Bool) -> some View {
        Button(action: action.action) {
            HStack(spacing: 6) {
                if action.isBusy {
                    ProgressView().controlSize(.small).tint(isPrimary ? .black : .white)
                } else if !isPrimary {
                    Image(systemName: action.systemImage).accessibilityHidden(true)
                }
                Text(action.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .padding(.horizontal, 8)
            .foregroundStyle(isPrimary ? Color.black : Color.white)
            .background(isPrimary ? Color.white : Color.black.opacity(0.24), in: Capsule())
            .opacity(action.isEnabled && !action.isBusy ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!action.isEnabled || action.isBusy)
        .accessibilityLabel(action.title)
        .accessibilityValue(action.detail ?? "")
    }
}
