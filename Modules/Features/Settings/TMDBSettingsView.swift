import SwiftUI

struct TMDBSettingsView: View {
    @AppStorage(TMDBSettings.enabledKey) private var enabled = false
    @State private var credentialDraft = ""
    @State private var hasCredential = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $enabled) {
                    SettingsRowLabel(localized("启用 TMDB 评分"), systemImage: "star.circle")
                }
                .accessibilityIdentifier("media.tmdb.enabled")

                SecureField(localized("TMDB API 密钥或 Read Access Token"), text: $credentialDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("media.tmdb.credential")
                Button(localized("保存 TMDB 凭证"), action: saveCredential)
                    .disabled(credentialDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("media.tmdb.save")
                if hasCredential {
                    LabeledContent(localized("凭证状态")) {
                        Text(localized("已安全保存；不会显示凭证内容"))
                            .foregroundStyle(DSColor.textSecondary)
                    }
                    Button(localized("移除 TMDB 凭证"), role: .destructive, action: removeCredential)
                        .accessibilityIdentifier("media.tmdb.remove")
                }
                Link(destination: URL(string: "https://www.themoviedb.org/settings/api")!) {
                    Label(localized("前往 TMDB 官方 API 密钥页面"), systemImage: "arrow.up.right.square")
                }
            } header: {
                Text(localized("TMDB 账户"))
                    .foregroundStyle(DSColor.textSecondary)
            } footer: {
                Text(localized("凭证只保存在此设备的 Keychain，不写入偏好设置或日志。查询仅发送至 TMDB 官方 HTTPS API；关闭评分或未配置凭证时不会请求。v3 密钥通过查询参数发送，v4 Read Access Token 通过授权标头发送。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()

            Section {
                Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
            } header: {
                Text(localized("数据来源与署名"))
                    .foregroundStyle(DSColor.textSecondary)
            }
            .interfaceSectionSurface()
        }
        .softScrollEdges()
        .themedAppSurface(for: .settings)
        .navigationTitle(localized("TMDB 评分"))
        .toolbarTitleDisplayMode(.inline)
        .onAppear { hasCredential = TMDBSettings.credential?.isEmpty == false }
        .alert(localized("TMDB 凭证"), isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } }
        )) {
            Button(localized("好"), role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func saveCredential() {
        do {
            try TMDBSettings.saveCredential(credentialDraft)
            credentialDraft = ""
            hasCredential = true
        } catch {
            message = localized("无法安全保存 TMDB 凭证，请稍后重试。")
        }
    }

    private func removeCredential() {
        do {
            try TMDBSettings.deleteCredential()
            credentialDraft = ""
            hasCredential = false
        } catch {
            message = localized("无法移除 TMDB 凭证，原设置未更改。")
        }
    }
}

#Preview("TMDB") {
    NavigationStack { TMDBSettingsView() }
}
