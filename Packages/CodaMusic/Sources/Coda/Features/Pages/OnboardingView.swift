import SwiftUI

/// First-launch guide in one sheet: the disclaimer, then platform sign-in.
/// `steps` holds only what this user still needs (see `FirstLaunchOnboarding`).
struct OnboardingView: View {
    enum Step: Hashable { case disclaimer, signIn }

    var steps: [Step] = [.disclaimer, .signIn]
    /// Called when the disclaimer is accepted, before moving on.
    var onAcceptDisclaimer: () -> Void = {}
    /// Quits the app on first launch; the preview only closes.
    var onDeclineDisclaimer: (() -> Void)? = nil
    var onFinish: () -> Void

    @ObservedObject private var account = AccountStore.shared
    @ObservedObject private var manager = MusicAccountManager.shared
    @State private var loginProvider: MusicProvider?
    @State private var index = 0

    private var current: Step { steps.indices.contains(index) ? steps[index] : .signIn }

    var body: some View {
        VStack(spacing: 0) {
            if steps.count > 1 {
                HStack(spacing: 6) {
                    ForEach(steps.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == index ? Theme.accent : Color.secondary.opacity(0.3))
                            .frame(width: i == index ? 18 : 6, height: 6)
                    }
                }
                .padding(.top, 14)
                .animation(.spring(duration: 0.3), value: index)
                .accessibilityElement()
                .accessibilityLabel("第 \(index + 1) 步，共 \(steps.count) 步")
            }
            ZStack {
                switch current {
                case .disclaimer:
                    DisclaimerView(onAgree: {
                        onAcceptDisclaimer()
                        advance()
                    }, onDecline: onDeclineDisclaimer)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))
                case .signIn:
                    signInPage
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        #if os(macOS)
        .frame(width: 480, height: 640)
        #endif
        .interactiveDismissDisabled()
        .sheet(item: $loginProvider) { provider in
            LoginSheet(addingProvider: provider)
                .environmentObject(account)
        }
        // Signing in activates the new account; the guide is done.
        .onChange(of: account.isLoggedIn) { loggedIn in
            guard loggedIn, current == .signIn else { return }
            loginProvider = nil
            onFinish()
        }
    }

    private func advance() {
        if index + 1 < steps.count {
            withAnimation(.spring(duration: 0.4)) { index += 1 }
        } else {
            onFinish()
        }
    }

    private var signInPage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            appIcon
                .resizable()
                .scaledToFit()
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                .accessibilityHidden(true)
            Text("欢迎使用 Coda")
                .font(.system(size: 28, weight: .bold))
                .padding(.top, 20)
            Text("登录音乐平台账号，同步歌单、每日推荐和会员音质。之后可在设置中添加更多账号并随时切换。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .padding(.horizontal, 8)

            VStack(spacing: 10) {
                ForEach(MusicProvider.allCases) { provider in
                    Button { loginProvider = provider } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 20))
                                .foregroundStyle(Theme.accent)
                            Text("登录\(provider.name)")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.quaternary.opacity(0.6)))
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(manager.isSwitching)
                }
            }
            .padding(.top, 28)

            Spacer(minLength: 24)
            Button("稍后再说", action: onFinish)
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
    }

    private var appIcon: Image {
        #if os(macOS)
        Image(nsImage: NSApplication.shared.applicationIconImage)
        #else
        Image("CodaLogo")
        #endif
    }
}

/// Presents the first-launch guide: the disclaimer until its current version is
/// accepted (every user), and the sign-in step only for users without any account.
struct FirstLaunchOnboarding: ViewModifier {
    var onDeclineInHost: (() -> Void)? = nil
    // Shared instance: on iOS this modifier sits outside the window's environmentObject injection.
    @ObservedObject private var account = AccountStore.shared
    @AppStorage("onboarding.completed") private var completed = false
    @AppStorage(Disclaimer.acceptedVersionKey) private var acceptedDisclaimer = 0
    @State private var steps: [OnboardingView.Step] = []
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .task {
                guard !CodaPaths.isOfflineUITest else { return }
                // Existing users (saved accounts or an active session) skip the sign-in step.
                if !completed, account.hasAuthCookie || !MusicAccountManager.shared.accounts.isEmpty {
                    completed = true
                }
                var pending: [OnboardingView.Step] = []
                if acceptedDisclaimer < Disclaimer.version { pending.append(.disclaimer) }
                if !completed { pending.append(.signIn) }
                steps = pending
                isPresented = !pending.isEmpty
            }
            .sheet(isPresented: $isPresented) {
                OnboardingView(steps: steps,
                               onAcceptDisclaimer: { acceptedDisclaimer = Disclaimer.version },
                               onDeclineDisclaimer: declineHandler,
                               onFinish: { completed = true; isPresented = false })
                    .environmentObject(account)
            }
    }

    /// Declining quits. iOS has no public quit API: return to the Home Screen
    /// first (the system suspend animation), then exit. The disclaimer stays
    /// unaccepted, so it is shown again on next launch.
    private var declineHandler: (() -> Void)? {
        if ReadccHostBridge.isEmbedded {
            return {
                // Do not accept the disclaimer or mark onboarding complete on rejection.
                isPresented = false
                onDeclineInHost?()
            }
        }
        #if os(macOS)
        return { NSApplication.shared.terminate(nil) }
        #else
        return {
            UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { exit(0) }
        }
        #endif
    }
}
