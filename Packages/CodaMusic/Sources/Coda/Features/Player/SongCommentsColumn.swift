import SwiftUI

struct SongCommentsColumn: View {
    let track: Track
    @ObservedObject private var model: SongCommentsStore
    @EnvironmentObject private var account: AccountStore
    @Environment(\.openLogin) private var openLogin
    @Environment(\.nowPlayingFlushPanelEdges) private var flushPanelEdges
    @FocusState private var isComposing: Bool
    @State private var deleting: SongComment?
    @State private var keyboardFrame = CGRect.null
    @State private var keyboardWindow = CGRect.zero

    init(track: Track, model: SongCommentsStore) {
        self.track = track
        self.model = model
    }

    var body: some View {
        GeometryReader { geometry in
            column
                .padding(.bottom, SongCommentsKeyboardLayout.bottomInset(
                    column: geometry.frame(in: .global), keyboard: keyboardFrame, window: keyboardWindow
                ))
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) {
            updateKeyboard($0)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) {
            updateKeyboard($0, hiding: true)
        }
        #endif
        .task(id: account.authenticatedAccountID) {
            await model.open(accountID: account.authenticatedAccountID)
        }
        .alert("评论操作失败", isPresented: Binding(
            get: { model.actionError != nil },
            set: { if !$0 { model.actionError = nil } }
        )) {
            Button("好", role: .cancel) { model.actionError = nil }
        } message: {
            Text(model.actionError ?? "")
        }
        .confirmationDialog("删除这条评论？", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible) {
            if let comment = deleting {
                Button("删除评论", role: .destructive) {
                    Task { await model.delete(comment) }
                    deleting = nil
                }
            }
            Button("取消", role: .cancel) { deleting = nil }
        }
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.component) {
            HStack(alignment: .center, spacing: Theme.Spacing.component) {
                Text("歌曲评论")
                    .font(Theme.Typography.sectionTitle.weight(.bold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                Picker("评论排序", selection: Binding(
                    get: { model.sort },
                    set: { sort in Task { await model.select(sort) } }
                )) {
                    Text("热门").tag(SongCommentSort.hot)
                    Text("最新").tag(SongCommentSort.latest)
                }
                .pickerStyle(.segmented)
                .frame(width: 164)
                .disabled(model.isSubmitting)
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if account.provider == .netease { composer }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, flushPanelEdges ? 0 : Theme.Layout.contentInset)
        .padding(.top, flushPanelEdges ? 0 : Theme.Spacing.component)
        .padding(.bottom, flushPanelEdges ? 0 : Theme.Spacing.small)
    }

    #if os(iOS)
    private func updateKeyboard(_ notification: Notification, hiding: Bool = false) {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .filter({ $0.activationState == .foregroundActive })
            .flatMap(\.windows).first(where: \.isKeyWindow) else { return }
        let info = notification.userInfo ?? [:]
        let screenFrame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect ?? .null
        let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        withAnimation(.easeOut(duration: duration)) {
            keyboardWindow = window.bounds
            keyboardFrame = hiding || screenFrame.isNull
                ? .null : window.convert(screenFrame, from: window.screen.coordinateSpace)
        }
    }

    #endif

    private var content: some View {
        // Keep this ScrollView mounted throughout loading and refreshing. Its
        // refreshable task belongs to the scroll view's lifetime.
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.section) {
                if model.comments.isEmpty {
                    if model.isLoading {
                        ProgressView().tint(.white)
                            .frame(maxWidth: .infinity, minHeight: 140)
                    } else if let error = model.errorMessage {
                        VStack(spacing: Theme.Spacing.component) {
                            Text(error).foregroundStyle(.white.opacity(0.65))
                            Button("重新加载") { Task { await model.reload() } }
                                .buttonStyle(.bordered)
                            if account.authenticatedAccountID == nil {
                                Button("登录网易云音乐", action: openLogin)
                            }
                        }
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 140)
                    } else {
                        Text("还没有评论，来说说你的感受吧")
                            .font(Theme.Typography.body)
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: .infinity, minHeight: 140)
                    }
                }
                if let error = model.refreshError {
                    VStack(spacing: Theme.Spacing.small) {
                        Text(error).font(Theme.Typography.caption).foregroundStyle(.white.opacity(0.6))
                        Button("重新刷新") { Task { await model.reload() } }
                    }
                    .frame(maxWidth: .infinity)
                }
                ForEach(model.comments) { comment in
                    commentRow(comment)
                }
                if model.hasMore {
                    VStack(spacing: Theme.Spacing.small) {
                        if let error = model.loadMoreError {
                            Text(error).font(Theme.Typography.caption).foregroundStyle(.white.opacity(0.6))
                        }
                        Button {
                            Task { await model.loadMore() }
                        } label: {
                            if model.isLoadingMore { ProgressView().tint(.white) }
                            else { Text(model.loadMoreError == nil ? "加载更多" : "重试") }
                        }
                        .disabled(model.isLoading || model.isLoadingMore)
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }
            .padding(.vertical, Theme.Spacing.control)
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        .refreshable { await model.reload() }
    }

    private func commentRow(_ comment: SongComment) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.control) {
            CachedAsyncImage(url: comment.user.avatarUrl?.resizedImageURL(96), animated: false)
                .frame(width: 34, height: 34)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                        Text(comment.user.nickname)
                            .font(Theme.Typography.secondary.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                        Text(comment.date, style: .date)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer(minLength: 4)
                    Button {
                        if requiresLogin() { return }
                        Task { await model.toggleLike(comment) }
                    } label: {
                        HStack(spacing: Theme.Spacing.tight) {
                            Text(comment.likedCount.formatted()).font(Theme.Typography.caption)
                            Image(systemName: comment.liked ? "hand.thumbsup.fill" : "hand.thumbsup")
                                .font(.system(size: 14))
                        }
                        .foregroundStyle(.white.opacity(comment.liked ? 1 : 0.5))
                        .frame(minWidth: 44, minHeight: 34)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.busyCommentIDs.contains(comment.id))
                    .accessibilityLabel(comment.liked ? "取消点赞" : "点赞评论")
                    .disabled(account.provider != .netease)
                }
                Text(comment.content)
                    .font(Theme.Typography.body)
                    .foregroundStyle(.white.opacity(0.9))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(comment.beReplied.enumerated()), id: \.offset) { _, reply in
                    Text((reply.user.map { "@\($0.nickname)：" } ?? "")
                         + (reply.content ?? String(localized: "原评论已删除")))
                        .font(Theme.Typography.secondary)
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(Theme.Spacing.control)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
                Button("回复") {
                    if requiresLogin() { return }
                    model.replyingTo = comment
                    isComposing = true
                }
                .disabled(account.provider != .netease)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .buttonStyle(.plain)
            }
        }
        .contextMenu {
            Button("回复") {
                if requiresLogin() { return }
                model.replyingTo = comment
                isComposing = true
            }
            .disabled(account.provider != .netease)
            if account.authenticatedAccountID == comment.user.userId {
                Button("删除评论", role: .destructive) { deleting = comment }
            }
        }
    }

    @ViewBuilder
    private var composer: some View {
        if account.authenticatedAccountID == nil {
            Button(action: openLogin) {
                Text("登录后参与评论")
                    .font(Theme.Typography.body.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                if let reply = model.replyingTo {
                    HStack {
                        Text("回复 @\(reply.user.nickname)")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                        Spacer()
                        Button { model.replyingTo = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(width: 32, height: 32)
                        }
                        .accessibilityLabel("取消回复")
                    }
                }
                HStack(alignment: .bottom, spacing: Theme.Spacing.control) {
                    TextField("写下你的感受…", text: $model.draft, axis: .vertical)
                        .font(Theme.Typography.body)
                        .lineLimit(1...4)
                        .focused($isComposing)
                        .disabled(model.isSubmitting)
                        .padding(Theme.Spacing.control)
                        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                    Button {
                        Task {
                            if await model.send() {
                                isComposing = false
                                ToastCenter.shared.show(String(localized: "评论已发送"))
                            }
                        }
                    } label: {
                        Group {
                            if model.isSubmitting { ProgressView().tint(.white) }
                            else { Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold)) }
                        }
                        .frame(width: 42, height: 42)
                        .background(.white.opacity(0.15), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isSubmitting || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel(model.replyingTo == nil ? "发送评论" : "发送回复")
                }
            }
        }
    }

    private func requiresLogin() -> Bool {
        guard account.authenticatedAccountID != nil else {
            openLogin()
            return true
        }
        return false
    }
}
/// Frames are in the hosting window's coordinates, including in Split View.
/// Floating keyboards should not resize an entire column.
enum SongCommentsKeyboardLayout {
    static func bottomInset(column: CGRect, keyboard: CGRect, window: CGRect) -> CGFloat {
        guard !keyboard.isNull, !keyboard.isEmpty, !window.isEmpty,
              keyboard.width >= window.width * 0.9,
              keyboard.maxY >= window.maxY - 1,
              column.intersects(keyboard) else { return 0 }
        return min(column.height, max(0, column.maxY - keyboard.minY + 12))
    }
}
