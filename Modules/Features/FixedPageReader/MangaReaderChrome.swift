import SwiftUI

/// Blank canvas gutters, not image trimming. The decoder and image contents are unchanged.

/// Only the manga top row is rearranged. Six unchanged 44pt button hit targets fit
/// a 320pt screen; the chapter title is the only compressible item. Root tabs are unrelated.
struct MangaReaderTopBar: View {
    let chapterTitle: String
    let isModal: Bool
    let isLoading: Bool
    let hasChapters: Bool
    let onClose: () -> Void
    let onContents: () -> Void
    let onRefresh: () -> Void
    let onSettings: () -> Void
    var onOfflineCache: (() -> Void)? = nil
    var onChangeSource: (() -> Void)? = nil
    var offlineCacheEnabled = true
    @Bindable private var settings = GlobalSettings.shared

    var body: some View {
        HStack(spacing: 0) {
            control(isModal ? "xmark" : "chevron.left",
                    label: localized(isModal ? "關閉" : "返回"), id: "manga.close", action: onClose)
            if hasChapters {
                control("list.bullet", label: localized("目錄"), id: "manga.contents", action: onContents)
            }
            if let onOfflineCache {
                control(ReaderChromeActionItem.download.defaultSystemImage,
                        label: localized("离线缓存"), id: "manga.offlineCache", action: onOfflineCache)
                    .disabled(!offlineCacheEnabled)
            }
            Text(chapterTitle)
                .font(DSFont.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 0, maxWidth: .infinity)
                .accessibilityIdentifier("manga.chapterTitle")
            Button(action: onRefresh) {
                refreshGlyph
                    .frame(width: 20, height: 20)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(localized(ReaderChromeActionItem.refresh.titleKey))
            .accessibilityIdentifier("manga.refresh")
            .accessibilityAction {
                guard !isLoading else { return }
                onRefresh()
            }
            .disabled(isLoading)
            if let onChangeSource {
                control(ReaderChromeActionItem.changeSource.defaultSystemImage,
                        label: localized("換源"), id: "manga.changeSource", action: onChangeSource)
            }
            control("slider.horizontal.3", label: localized("閱讀設定"), id: "manga.settings", action: onSettings)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .readccGlassSurface(cornerRadius: 22, onDark: true)
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("manga.topBar")
    }

    @ViewBuilder private var refreshGlyph: some View {
        if let custom = settings.readerChromeIconImage(for: ReaderChromeActionItem.refresh) {
            Image(uiImage: custom).renderingMode(.original).resizable().scaledToFit()
        } else {
            Image(systemName: ReaderChromeActionItem.refresh.defaultSystemImage)
                .font(.system(size: 20))
        }
    }

    private func control(_ symbol: String, label: String, id: String,
                         action: @escaping () -> Void) -> some View {
        MangaToolbarButton(symbol: symbol, label: label, identifier: id, action: action)
    }
}

private struct MangaToolbarButton: View {
    let symbol: String
    let label: String
    let identifier: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
        .accessibilityAction {
            guard isEnabled else { return }
            action()
        }
    }
}
