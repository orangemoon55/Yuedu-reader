import SwiftUI

/// Full disclaimer text. Bump `version` whenever the terms change in substance:
/// every user is asked to accept again on next launch.
enum Disclaimer {
    static let version = 3
    static let acceptedVersionKey = "disclaimer.acceptedVersion"

    struct Clause: Identifiable {
        let id: Int
        let title: String
        let body: String
    }

    static let summary = "使用 Coda 前，请仔细阅读以下条款。点按“同意并继续”即表示你已阅读、理解并接受全部内容。"

    static let clauses: [Clause] = [
        Clause(id: 1, title: "软件性质",
               body: "Coda 是开源的非官方第三方音乐客户端，与网易云音乐、QQ 音乐、酷狗音乐、汽水音乐及其关联公司均无隶属、合作、授权或背书关系。上述名称与商标归各自权利人所有，仅用于说明兼容的服务。"),
        Clause(id: 2, title: "内容与版权",
               body: "Coda 不存储、上传或分发任何音频内容。歌曲、歌词、封面、评论等均由你登录的音乐平台实时提供，版权归原权利人所有。请支持正版音乐，通过平台会员获取相应权益。"),
        Clause(id: 3, title: "第三方音源",
               body: "当前平台无法播放某首歌时，Coda 会自动从第三方镜像、解析服务及其他音乐平台匹配同一首歌播放，并使用你在这些平台保存的账号。这些音源不由 Coda 提供或控制，其可用性、准确性与合法性均无法保证，请自行判断，并遵守所在地法律法规。"),
        Clause(id: 4, title: "账号风险",
               body: "Coda 通过非官方接口访问平台服务，可能不符合相关平台的用户协议。由此可能导致登录失效、功能受限，甚至账号被限制或封禁，相关风险由你自行承担。请勿用于批量、自动化或其他异常访问。"),
        Clause(id: 5, title: "数据与隐私",
               body: "Coda 不设服务器，不收集个人信息或使用数据。登录凭证仅保存在本机钥匙串中，只用于向对应平台发送请求。“导出登录数据”生成的内容包含凭证，请勿分享给他人。检查更新时会访问 GitHub。"),
        Clause(id: 6, title: "下载与缓存",
               body: "下载和缓存的内容仅供你在本机离线收听，不得传播、分享或用于商业用途。会员到期或版权变更后，请删除相应内容。"),
        Clause(id: 7, title: "用途与许可",
               body: "本项目以个人学习、研究与交流为目的开发。请勿将本软件用于违反法律法规或侵犯他人合法权益的用途；通过本软件获取的音频、歌词、封面等内容不得用于商业用途或二次传播。本软件以 GNU AGPL v3.0 许可证发布，使用、修改与分发须遵守该许可证。"),
        Clause(id: 8, title: "无担保与责任限制",
               body: "本软件按“现状”提供，不保证持续可用、没有错误或适合特定用途。在法律允许的范围内，开发者不对因使用或无法使用本软件造成的任何直接或间接损失承担责任，包括但不限于账号封禁、数据丢失或设备问题。"),
        Clause(id: 9, title: "权利通知",
               body: "如果你认为本项目侵犯了你的合法权益，请通过 GitHub Issues 联系开发者，核实后将及时处理。"),
        Clause(id: 10, title: "条款变更",
               body: "本声明可能随版本更新而修订，修订后会再次请求你确认。如不同意本声明的任何内容，请停止使用并删除本软件。"),
    ]
}

/// Disclaimer page. With `onAgree`/`onDecline` it is the first-launch gate;
/// without them it is a read-only page with a close button.
struct DisclaimerView: View {
    var onAgree: (() -> Void)? = nil
    var onDecline: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showsDeclineNotice = false

    private var isGate: Bool { onAgree != nil }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "exclamationmark.shield")
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(Theme.accent)
                            .accessibilityHidden(true)
                        Text("免责声明")
                            .font(.system(size: 28, weight: .bold))
                            .accessibilityAddTraits(.isHeader)
                        Text(Disclaimer.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Disclaimer.clauses) { clause in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(clause.id). \(clause.title)")
                                .font(.headline)
                            Text(clause.body)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 600)
        #endif
        .interactiveDismissDisabled(isGate)
        .alert("需要同意免责声明", isPresented: $showsDeclineNotice) {
            Button("返回阅读", role: .cancel) {}
        } message: {
            Text("同意后才能使用 Coda。如不同意，请关闭并删除本应用。")
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let onAgree {
            VStack(spacing: 10) {
                Button(action: onAgree) {
                    Text("同意并继续")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                Button("不同意") {
                    if let onDecline { onDecline() } else { showsDeclineNotice = true }
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        } else {
            Button {
                dismiss()
            } label: {
                Text("关闭")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.bordered)
        }
    }
}
