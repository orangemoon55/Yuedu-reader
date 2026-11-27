import SwiftUI

/// Presentation state for the account section. Sheets, alerts and dialogs are
/// hosted on the settings Form (see `MusicAccountsPresenter`): on iOS a
/// presentation attached to a Section/row is torn down when the List re-renders.
@MainActor
final class MusicAccountsPresentation: ObservableObject {
    @Published var addingProvider: MusicProvider?
    @Published var errorMessage: String?
    @Published var pendingRemoval: MusicAccount?
    @Published var confirmsCredentialExport = false
}

struct MusicAccountsSection: View {
    @ObservedObject private var manager = MusicAccountManager.shared
    @ObservedObject var presentation: MusicAccountsPresentation

    var body: some View {
        Section("账号管理") {
            // Shared scrolling keeps iPadOS 16 finger taps on the cards and
            // their remove buttons near the row's top and bottom edges.
            ScenePreservingScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(manager.accounts) { item in accountCard(item) }
                    ForEach(guestProviders) { provider in guestCard(provider) }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .listRowInsets(EdgeInsets())
            .accessibilityIdentifier("musicAccountCards")
            .disabled(manager.isSwitching)
            Menu {
                ForEach(MusicProvider.allCases) { provider in
                    Button(provider.name) {
                        // Scanning adds the account to the list; the active platform stays as is.
                        presentation.addingProvider = provider
                    }
                }
            } label: {
                actionLabel("添加账号", systemImage: "person.badge.plus")
            }
            .modifier(AccountActionStyle(isMenu: true))
            .disabled(manager.isSwitching)
            Button {
                presentation.confirmsCredentialExport = true
            } label: {
                actionLabel("导出登录数据到剪贴板", systemImage: "square.and.arrow.up")
            }
            .modifier(AccountActionStyle())
            .disabled(manager.isSwitching)
            Button {
                do {
                    let count = try manager.importLoginData(Platform.pasteboardString ?? "")
                    ToastCenter.shared.show(count > 0 ? "已导入 \(count) 个账号，可在列表中切换" : "当前账号已登录，无需重复导入")
                } catch { presentation.errorMessage = error.localizedDescription }
            } label: {
                actionLabel("从剪贴板导入登录数据", systemImage: "square.and.arrow.down")
            }
            .modifier(AccountActionStyle())
            .disabled(manager.isSwitching)
            if manager.isSwitching { ProgressView("正在切换账号…") }
        }
        .task(id: "\(manager.currentID ?? "guest")|\(manager.accounts.map { "\($0.id):\($0.credentials.hashValue)" }.sorted().joined(separator: "|"))") {
            do { try manager.rememberCurrent() } catch { presentation.errorMessage = error.localizedDescription }
            await manager.refreshMemberships()
        }
    }
    private func accountCard(_ item: MusicAccount) -> some View {
        let isCurrent = manager.currentID == item.id
        return VStack(spacing: 8) {
            CachedAsyncImage(url: item.avatarURL.flatMap(URL.init(string:))) {
                ZStack {
                    Circle().fill(.quaternary.opacity(0.5))
                    Text(String(item.nickname.prefix(1)))
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(isCurrent ? Theme.accent : .clear, lineWidth: 2))
            .overlay(alignment: .bottomTrailing) {
                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white, Theme.accent)
                }
            }
            .padding(.top, 4)
            Text(item.nickname).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(item.provider.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(membershipTitle(item))
                .font(.caption)
                .foregroundStyle(item.membership?.membership.isMember == true ? Theme.accent : .secondary)
                .lineLimit(1)
        }
        .padding(.bottom, 4)
        .padding(12)
        .frame(width: 132)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.quaternary.opacity(isCurrent ? 0.9 : 0.5)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(isCurrent ? Theme.accent.opacity(0.6) : .clear, lineWidth: 1))
        .overlay(alignment: .topLeading) {
            AccountValidityBadge(status: manager.validity(for: item)).padding(12)
        }
        .overlay(alignment: .topTrailing) {
            Button(role: .destructive) { presentation.pendingRemoval = item } label: {
                Image(systemName: "minus.circle.fill").font(.system(size: 18)).foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .padding(8)
            .accessibilityLabel("移除\(item.nickname)")
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            guard !isCurrent else { return }
            Task { await perform { try await manager.select(item) } }
        }
        .contextMenu {
            if !isCurrent { Button("切换到此账号", systemImage: "arrow.left.arrow.right") { Task { await perform { try await manager.select(item) } } } }
            Button("移除账号", systemImage: "minus.circle", role: .destructive) { presentation.pendingRemoval = item }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [.isButton])
        .accessibilityHint(isCurrent ? "使用中" : "轻点切换到此账号")
    }
    /// Platforms without a saved account, plus the one currently browsed signed out.
    private var guestProviders: [MusicProvider] {
        let saved = Set(manager.accounts.map(\.provider))
        return MusicProvider.allCases.filter { !saved.contains($0) || manager.isBrowsingAsGuest($0) }
    }

    /// A blank card for a platform with no account: tapping browses it as a guest,
    /// and its login button adds an account for that platform.
    private func guestCard(_ provider: MusicProvider) -> some View {
        let isCurrent = manager.isBrowsingAsGuest(provider)
        return VStack(spacing: 8) {
            ZStack {
                Circle().strokeBorder(.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                Image(systemName: "person.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 72, height: 72)
            .overlay(Circle().strokeBorder(isCurrent ? Theme.accent : .clear, lineWidth: 2))
            .overlay(alignment: .bottomTrailing) {
                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white, Theme.accent)
                }
            }
            .padding(.top, 4)
            Text(isCurrent ? "游客" : "未登录").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
            Text(provider.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Button("登录") { presentation.addingProvider = provider }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .buttonStyle(.borderless)
                .lineLimit(1)
        }
        .padding(.bottom, 4)
        .padding(12)
        .frame(width: 132)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.quaternary.opacity(isCurrent ? 0.9 : 0.25)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(isCurrent ? Theme.accent.opacity(0.6) : Color.secondary.opacity(0.2),
                          style: StrokeStyle(lineWidth: 1, dash: isCurrent ? [] : [5, 4])))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            guard !isCurrent else { return }
            Task { await perform { try await manager.browseAsGuest(provider) } }
        }
        .contextMenu {
            if !isCurrent {
                Button("以游客身份浏览", systemImage: "arrow.left.arrow.right") {
                    Task { await perform { try await manager.browseAsGuest(provider) } }
                }
            }
            Button("登录\(provider.name)", systemImage: "person.badge.plus") { presentation.addingProvider = provider }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [.isButton])
        .accessibilityLabel("\(provider.name)，未登录")
        .accessibilityHint(isCurrent ? "正在以游客身份浏览" : "轻点以游客身份浏览")
    }

    /// The label spans the row so the whole row, not just its text, is tappable.
    private func actionLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }

    private func perform(_ action: () async throws -> Void) async {
        do { try await action() } catch { presentation.errorMessage = error.localizedDescription }
    }
    private func membershipTitle(_ item: MusicAccount) -> String { manager.membershipTitle(for: item) }
}

/// Whether the saved login still works on its platform: green valid, red expired,
/// gray while checking or when the platform cannot tell.
struct AccountValidityBadge: View {
    let status: MusicAccountValidity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Breathes while the check runs; the timeline is paused otherwise.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPulsing)) { context in
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .opacity(opacity(at: context.date))
        }
        .frame(width: 8, height: 8)
        .animation(.easeInOut(duration: 0.25), value: status)
        .help(status.rawValue)
        .accessibilityElement()
        .accessibilityLabel("登录状态：\(status.rawValue)")
    }

    private var isPulsing: Bool { status == .checking && !reduceMotion }

    private func opacity(at date: Date) -> Double {
        guard status == .checking else { return 1 }
        guard isPulsing else { return 0.5 }
        let phase = (sin(date.timeIntervalSinceReferenceDate * .pi / 0.75) + 1) / 2
        return 0.25 + 0.55 * phase
    }

    private var color: Color {
        switch status {
        case .valid: return .green
        case .invalid: return .red
        case .checking, .unknown: return .gray
        }
    }
}

/// macOS Forms draw Buttons bordered and Menus as native pop-up buttons with
/// their own icon metrics; render all account actions through one button style
/// and one label layout so icons share a column and titles line up.
private struct AccountActionStyle: ViewModifier {
    var isMenu = false

    func body(content: Content) -> some View {
        #if os(macOS)
        Group {
            if isMenu {
                content.menuStyle(.button).menuIndicator(.hidden)
            } else {
                content
            }
        }
        // Plain lets a Menu render its SwiftUI label instead of a native pop-up button.
        .buttonStyle(.plain)
        .labelStyle(AccountActionLabelStyle())
        .foregroundStyle(Theme.accent)
        .tint(Theme.accent)
        #else
        content
        #endif
    }
}

#if os(macOS)
private struct AccountActionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .frame(width: 20, alignment: .center)
            configuration.title
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
#endif

/// Apply to the settings Form, not to a Section, so presentations survive List updates.
struct MusicAccountsPresenter: ViewModifier {
    @ObservedObject var presentation: MusicAccountsPresentation
    @ObservedObject private var manager = MusicAccountManager.shared

    func body(content: Content) -> some View {
        content
            .sheet(item: $presentation.addingProvider) { LoginSheet(addingProvider: $0) }
            .confirmationDialog("导出可用于登录的账号凭据？", isPresented: $presentation.confirmsCredentialExport, titleVisibility: .visible) {
                Button("确认导出") {
                    do {
                        Platform.copySensitiveToPasteboard(string: try manager.exportLoginData())
                        ToastCenter.shared.show("登录数据已复制，请勿发给他人")
                    } catch { presentation.errorMessage = error.localizedDescription }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("导出内容包含所有已保存音乐账号的登录凭据。获得该内容的人可能以你的身份登录。iOS 剪贴板仅限本机并在两分钟后过期。")
            }
            .alert("账号操作失败", isPresented: Binding(get: { presentation.errorMessage != nil }, set: { if !$0 { presentation.errorMessage = nil } })) {
                Button("好", role: .cancel) { presentation.errorMessage = nil }
            } message: { Text(presentation.errorMessage ?? "") }
            .confirmationDialog("移除此账号？", isPresented: Binding(get: { presentation.pendingRemoval != nil }, set: { if !$0 { presentation.pendingRemoval = nil } }), titleVisibility: .visible) {
                if let item = presentation.pendingRemoval {
                    Button("移除账号", role: .destructive) {
                        Task {
                            do { try await manager.remove(item) } catch { presentation.errorMessage = error.localizedDescription }
                            presentation.pendingRemoval = nil
                        }
                    }
                }
                Button("取消", role: .cancel) { presentation.pendingRemoval = nil }
            } message: { Text("移除本机保存的登录凭证，之后可以重新登录。") }
    }
}

struct LoginSheet: View {
    /// Set when adding an account from account management: scan for this platform without switching to it.
    var addingProvider: MusicProvider? = nil
    @EnvironmentObject private var account: AccountStore
    var body: some View {
        let provider = addingProvider ?? account.provider
        if provider == .netease { NeteaseLoginSheet(addsAccount: addingProvider != nil) }
        else { PlatformLoginSheet(provider: provider, addsAccount: addingProvider != nil) }
    }
}
