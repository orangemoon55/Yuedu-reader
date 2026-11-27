// Temporary/ — 临时功能与测试入口。
// 这里只放临时调试、验证用的代码（例如在设置里手动唤出某个界面），
// 全部包在 `#if DEBUG` 中，不进入正式版；验证完成后可整块删除本目录及
// SettingsView 中对 `TemporarySettingsSection` 与 `showsOnboardingPreview` 的引用。

#if DEBUG
import SwiftUI

/// Debug-only settings section collecting temporary test entries.
/// Presentations are hosted by SettingsView on the Form (a sheet on a Section
/// is dismissed by iOS when the List re-renders); entries only call back.
struct TemporarySettingsSection: View {
    var showOnboarding: () -> Void

    var body: some View {
        Section {
            Button {
                showOnboarding()
            } label: {
                Label("显示首次启动向导（含免责声明）", systemImage: "sparkles")
            }
        } header: {
            Text("临时测试")
        } footer: {
            Text("仅开发版可见，用于预览临时功能；不会修改账号或向导完成状态。")
        }
    }
}
#endif
