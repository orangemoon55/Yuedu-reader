import SwiftUI
import WebKit

/// Host the official verification component. The native controls reuse the
/// existing login typography and spacing; the verification UI belongs to Qishui.
struct QishuiSecurityVerificationView: View {
    let webView: WKWebView
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.component) {
            Text("汽水音乐安全验证").font(Theme.Typography.sectionTitle)
            QishuiVerificationBrowser(webView: webView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button("取消验证", action: onCancel).buttonStyle(.plain)
        }
        .padding(Theme.Layout.contentInset)
        #if os(macOS)
        .frame(minWidth: 760, minHeight: 600)
        #endif
    }
}

#if os(macOS)
private struct QishuiVerificationBrowser: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#else
private struct QishuiVerificationBrowser: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
