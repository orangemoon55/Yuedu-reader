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
                    SettingsRowLabel(localized("啟用 TMDB 評分"), systemImage: "star.circle")
                }
                .accessibilityIdentifier("media.tmdb.enabled")

                SecureField(localized("TMDB API 金鑰或 Read Access Token"), text: $credentialDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("media.tmdb.credential")
                Button(localized("儲存 TMDB 憑證"), action: saveCredential)
                    .disabled(credentialDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("media.tmdb.save")
                if hasCredential {
                    LabeledContent(localized("憑證狀態")) {
                        Text(localized("已安全儲存；不會顯示憑證內容"))
                            .foregroundStyle(DSColor.textSecondary)
                    }
                    Button(localized("移除 TMDB 憑證"), role: .destructive, action: removeCredential)
                        .accessibilityIdentifier("media.tmdb.remove")
                }
                Link(destination: URL(string: "https://www.themoviedb.org/settings/api")!) {
                    Label(localized("前往 TMDB 官方 API 金鑰頁面"), systemImage: "arrow.up.right.square")
                }
            } header: {
                Text(localized("TMDB 帳戶"))
                    .foregroundStyle(DSColor.textSecondary)
            } footer: {
                Text(localized("憑證只保存在此裝置的 Keychain，不會寫入偏好設定或日誌。查詢只傳送至 TMDB 官方 HTTPS API；關閉評分或未設定憑證時不會發出請求。v3 金鑰以查詢參數傳送，v4 Read Access Token 以授權標頭傳送。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()

            Section {
                Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
            } header: {
                Text(localized("資料來源與 attribution"))
                    .foregroundStyle(DSColor.textSecondary)
            }
            .interfaceSectionSurface()
        }
        .softScrollEdges()
        .themedAppSurface(for: .settings)
        .navigationTitle(localized("TMDB 評分"))
        .toolbarTitleDisplayMode(.inline)
        .onAppear { hasCredential = TMDBSettings.credential?.isEmpty == false }
        .alert(localized("TMDB 憑證"), isPresented: Binding(
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
            message = localized("無法安全儲存 TMDB 憑證，請稍後再試。")
        }
    }

    private func removeCredential() {
        do {
            try TMDBSettings.deleteCredential()
            credentialDraft = ""
            hasCredential = false
        } catch {
            message = localized("無法移除 TMDB 憑證，原設定未變更。")
        }
    }
}

#Preview("TMDB") {
    NavigationStack { TMDBSettingsView() }
}
