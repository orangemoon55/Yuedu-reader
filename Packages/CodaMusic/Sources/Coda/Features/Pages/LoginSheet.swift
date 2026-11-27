import CoreImage.CIFilterBuiltins
import SwiftUI

struct NeteaseLoginSheet: View {
    /// Adds the scanned account to the list instead of signing in on the shared session.
    var addsAccount = false

    private enum Phase: Equatable {
        case loading
        case waiting          // 801
        case scanned(String)  // 802, nickname
        case expired          // 800
        case success
        case failed(String)
    }

    @State private var phase: Phase = .loading
    @State private var qrImage: PlatformImage?
    @State private var unikey: String?
    @State private var pollTask: Task<Void, Never>?
    /// Holds the new account's cookies while adding, so the active session is never touched.
    @State private var isolatedClient = NeteaseClient(configuration: .ephemeral, persistsCookies: false)

    @EnvironmentObject private var account: AccountStore
    // Shared instance: the macOS Settings scene presents this sheet outside the main window's environment.
    @ObservedObject private var toasts = ToastCenter.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: Theme.Spacing.section) {
            Text(addsAccount ? "添加网易云音乐账号" : "登录网易云音乐")
                .font(Theme.Typography.sectionTitle)
                .padding(.top, Theme.Spacing.section)

            qrSection

            Button("取消") {
                dismiss()
            }
            .buttonStyle(.plain)
            .font(Theme.Typography.caption)
            .foregroundStyle(.secondary)
            .padding(.bottom, Theme.Spacing.section)
        }
        .frame(width: 320)
        .overlay(alignment: .top) {
            if let toast = toasts.current { ToastView(toast: toast).padding(.top, Theme.Spacing.small) }
        }
        .onAppear { startLogin() }
        .onDisappear { pollTask?.cancel() }
        // Coming back from the NetEase app (single-device flow): if polling
        // died while we were in the background, pick it up again.
        .onChange(of: scenePhase) { _ in
            guard scenePhase == .active else { return }
            if case .failed = phase { startLogin(reusingKey: true) }
            else if pollTask == nil || pollTask?.isCancelled == true { startLogin(reusingKey: true) }
        }
    }

    // MARK: - QR

    private var qrSection: some View {
        VStack(spacing: Theme.Spacing.section) {
            Text("使用网易云音乐 App 扫码登录")
                .font(Theme.Typography.caption)
                .foregroundStyle(.secondary)

            LoginQRCodeFrame(image: qrImage, obscuresImage: overlayVisible) {
                if overlayVisible {
                    VStack(spacing: Theme.Spacing.small) {
                        switch phase {
                        case .expired:
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .font(.system(size: 34))
                                .foregroundStyle(Theme.accent)
                            Text("二维码已失效")
                                .font(Theme.Typography.caption.weight(.medium))
                            Button("刷新") {
                                startLogin()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.accent)
                            .controlSize(.small)
                        case .scanned(let nickname):
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 34))
                                .foregroundStyle(.green)
                            Text("已扫码")
                                .font(Theme.Typography.body.weight(.semibold))
                            Text("\(nickname)，请在手机上确认")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(.secondary)
                        default:
                            EmptyView()
                        }
                    }
                    .padding(Theme.Spacing.control)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }

            Group {
                switch phase {
                case .loading:
                    Text("正在获取二维码…")
                case .waiting:
                    Text("打开网易云音乐 App，扫一扫登录")
                case .scanned:
                    Text("等待手机确认…")
                case .expired:
                    Text("二维码已失效，请刷新")
                case .success:
                    Text("登录成功！")
                case .failed(let message):
                    Text(message).foregroundStyle(Theme.accent)
                }
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(.secondary)

            #if os(iOS)
            Text("只有一台设备？截图二维码，到网易云音乐 App 的扫一扫里选择相册识别，然后回到这里即可")
                .font(Theme.Typography.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Layout.contentInset)
            #endif
        }
    }

    private var overlayVisible: Bool {
        switch phase {
        case .expired, .scanned: return true
        default: return false
        }
    }

    /// Starts (or resumes) the QR login. Polling tolerates transient network
    /// errors (the app being backgrounded while the user scans) instead of
    /// giving up on the first failure.
    private func startLogin(reusingKey: Bool = false) {
        pollTask?.cancel()
        let existingKey = reusingKey ? unikey : nil
        if existingKey == nil {
            phase = .loading
            qrImage = nil
        } else {
            phase = .waiting
        }
        pollTask = Task {
            do {
                let key: String
                if let existingKey {
                    key = existingKey
                } else {
                    key = addsAccount ? try await NeteaseAPI.qrKey(using: isolatedClient) : try await NeteaseAPI.qrKey()
                    unikey = key
                    qrImage = Self.generateQR(from: NeteaseAPI.qrLoginURL(unikey: key))
                    phase = .waiting
                }

                var consecutiveErrors = 0
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(1.2))
                    let check: NeteaseAPI.QRCheckResponse
                    do {
                        check = addsAccount
                            ? try await NeteaseAPI.qrCheck(unikey: key, using: isolatedClient)
                            : try await NeteaseAPI.qrCheck(unikey: key)
                        consecutiveErrors = 0
                    } catch {
                        consecutiveErrors += 1
                        if consecutiveErrors >= 15 { throw error }
                        continue
                    }
                    switch check.code {
                    case 800:
                        phase = .expired
                        unikey = nil
                        return
                    case 801:
                        if case .waiting = phase {} else { phase = .waiting }
                    case 802:
                        phase = .scanned(check.nickname ?? "")
                    case 803 where addsAccount:
                        let item = try await MusicAccountManager.shared.addAccount(
                            provider: .netease, credentials: isolatedClient.authenticationCookies(), nickname: check.nickname ?? "")
                        phase = .success
                        ToastCenter.shared.show(MusicAccountManager.shared.addedMessage(for: item))
                        dismiss()
                        return
                    case 803:
                        phase = .success
                        PlayerService.shared.resetForMusicAccountChange()
                        await account.bootstrap()
                        ToastCenter.shared.show(String(localized: "欢迎回来，\(account.profile?.nickname ?? "")"))
                        dismiss()
                        return
                    default:
                        break
                    }
                }
            } catch {
                if !Task.isCancelled {
                    phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    private static func generateQR(from string: String) -> PlatformImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        #if os(macOS)
        return NSImage(cgImage: cgImage, size: NSSize(width: 180, height: 180))
        #elseif os(iOS)
        return UIImage(cgImage: cgImage)
        #endif
    }
}
