import SwiftUI
import CoreImage.CIFilterBuiltins

struct PlatformLoginSheet: View {
    let provider: MusicProvider
    /// Adds the scanned account to the list instead of switching to it.
    var addsAccount = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var account: AccountStore
    @State private var image: PlatformImage?
    @State private var qqChannel = QQMusicLoginChannel.qq
    @State private var status = "正在获取二维码…"
    @State private var refresh = UUID()
    @State private var isSaving = false
    @StateObject private var qishuiAuth = QishuiMusicAPI(diagnostics: true)
    @StateObject private var qqAuth = QQMusicAuth(persistsSession: false)

    var body: some View {
        VStack(spacing: Theme.Spacing.section) {
            Text(addsAccount ? "添加\(provider.name)账号" : "登录\(provider.name)").font(Theme.Typography.sectionTitle)
                .padding(.top, Theme.Spacing.section)
            if provider == .qq {
                Picker("扫码方式", selection: $qqChannel) {
                    ForEach(QQMusicLoginChannel.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .disabled(isSaving)
                .onChange(of: qqChannel) { _ in refresh = UUID() }
            }
            Text(provider == .qishui ? "请使用已登录的汽水音乐 App 扫码并确认登录" : provider == .qq ? "请使用\(qqChannel.name)扫描二维码并确认登录" : "请使用酷狗音乐扫描二维码并确认登录")
                .font(Theme.Typography.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            LoginQRCodeFrame(image: image) { EmptyView() }
            Text(status).font(Theme.Typography.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("刷新二维码") { refresh = UUID() }
                .buttonStyle(.plain).font(Theme.Typography.caption).foregroundStyle(Theme.accent)
                .disabled(isSaving)
            Button("取消") { dismiss() }
                .buttonStyle(.plain).font(Theme.Typography.caption).foregroundStyle(.secondary)
                .padding(.bottom, Theme.Spacing.section).disabled(isSaving)
        }
        .frame(width: 320)
        .interactiveDismissDisabled(isSaving)
        .task(id: refresh) { await login() }
        .onDisappear { if provider == .qishui { qishuiAuth.cancelLogin() } }
        .sheet(isPresented: Binding(get: { qishuiAuth.verificationWebView != nil }, set: { if !$0 { qishuiAuth.cancelVerification() } })) {
            if let web = qishuiAuth.verificationWebView {
                QishuiSecurityVerificationView(webView: web, onCancel: { qishuiAuth.cancelVerification() })
            }
        }
    }
    private func login() async {
        image = nil
        status = "正在获取二维码…"
        do {
            if provider == .qishui { try await loginQishui(); return }
            if provider == .qq, qqChannel != .qq {
                let channel = qqChannel
                let result = try await QQMusicAdditionalLogin.signIn(channel, onImage: { data in
                    image = PlatformImage(data: data)
                    status = "等待使用\(channel.name)扫码"
                }, onScanned: {
                    status = "已扫码，请在\(channel.name)中确认"
                })
                try Task.checkCancellation()
                await finish(credentials: result.credentials, nickname: result.nickname)
                return
            }
            var key = ""
            if provider == .qq {
                let data = try await qqAuth.fetchQRCode()
                try Task.checkCancellation()
                image = PlatformImage(data: data)
            } else {
                let qr = try await KugouMusicAPI.shared.qrKey()
                try Task.checkCancellation()
                key = qr.key
                image = Self.qrImage(qr.url)
            }
            status = "等待扫码"
            while !Task.isCancelled {
                try await Task.sleep(for: .seconds(3))
                if provider == .qq {
                    let state = try await qqAuth.poll()
                    try Task.checkCancellation()
                    switch state {
                    case .waiting: status = "等待扫码"
                    case .scanned: status = "已扫码，请在 QQ 中确认"
                    case .expired: status = "二维码已过期，请刷新"; return
                    case .error(let message): status = message; return
                    case .success(let nickname): await finish(credentials: qqAuth.exportedCredentials, nickname: nickname); return
                    }
                } else {
                    let state = try await KugouMusicAPI.shared.pollQR(key: key)
                    try Task.checkCancellation()
                    switch state {
                    case .waiting: status = "等待扫码"
                    case .scanned: status = "已扫码，请在酷狗音乐中确认"
                    case .expired: status = "二维码已过期，请刷新"; return
                    case .error(let message): status = message; return
                    case .success(let credentials): await finish(credentials: credentials, nickname: credentials["nickname"] ?? "酷狗音乐用户"); return
                    }
                }
            }
        } catch is CancellationError { return }
        catch { if !Task.isCancelled { status = error.localizedDescription } }
    }
    private func loginQishui() async throws {
        let qr = try await qishuiAuth.qrCode()
        try Task.checkCancellation()
        guard let decoded = Self.qrImage(qr.scanURL.absoluteString) else { throw QishuiError.invalidResponse }
        image = decoded
        status = "等待使用汽水音乐扫码"
        while !Task.isCancelled {
            try await Task.sleep(for: .seconds(3))
            if qishuiAuth.isQRCodeExpired(token: qr.token) { status = "二维码已过期，请刷新"; return }
            let state = try await qishuiAuth.pollQRCode(token: qr.token)
            try Task.checkCancellation()
            switch state {
            case .waiting: status = "等待使用汽水音乐扫码"
            case .scanned: status = "已扫码，请在汽水音乐中确认"
            case .processing: status = "正在等待平台完成登录，请稍候…"
            case .expired: status = "二维码已过期，请刷新"; return
            case .confirmed(let credentials):
                await finish(credentials: credentials, nickname: credentials["nickname"] ?? "汽水音乐用户")
                return
            }
        }
    }
    private func finish(credentials: [String: String], nickname: String) async {
        isSaving = true
        defer { isSaving = false }
        do {
            if addsAccount {
                let item = try await MusicAccountManager.shared.addAccount(provider: provider, credentials: credentials, nickname: nickname)
                ToastCenter.shared.show(MusicAccountManager.shared.addedMessage(for: item))
            } else {
                try await MusicAccountManager.shared.saveAndActivate(provider: provider, credentials: credentials, nickname: nickname)
            }
            dismiss()
        } catch { status = error.localizedDescription }
    }
    private static func qrImage(_ value: String) -> PlatformImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        guard let output = filter.outputImage?.transformed(by: .init(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        #if os(macOS)
        return NSImage(cgImage: cg, size: NSSize(width: 200, height: 200))
        #else
        return UIImage(cgImage: cg)
        #endif
    }
}
