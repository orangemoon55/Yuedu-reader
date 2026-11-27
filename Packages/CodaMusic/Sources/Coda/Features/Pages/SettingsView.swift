import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var account: AccountStore
    @StateObject private var accountsPresentation = MusicAccountsPresentation()
    @Environment(\.openDestination) private var openDestination
    @StateObject private var storageModel = StorageSpaceModel()
    @State private var pendingStorageDeletion: StorageItem?
    @State private var automaticCacheLimitMB: Int?
    @State private var showsDisclaimer = false
    #if DEBUG
    @State private var showsOnboardingPreview = false
    #endif

    /// iPhone presents settings in a sheet with its own stack; Mac and iPad
    /// show them in the main content column and push shared destinations.
    private enum SettingsPage: Hashable {
        case licenses
    }

    private var usesMainColumn: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        true
        #endif
    }

    var body: some View {
        settingsForm
            .accessibilityIdentifier("settingsForm")
    }

    private var settingsForm: some View {
        Form {
            Group {
                MusicAccountsSection(presentation: accountsPresentation)
                #if DEBUG
                TemporarySettingsSection(showOnboarding: { showsOnboardingPreview = true })
                #endif
                #if os(macOS)

                AutoMixSettingsSection()
                #endif

                #if os(macOS)
                Section("外观") {
                    Toggle("桌面歌词", isOn: $settings.showDesktopLyrics)
                    if settings.showDesktopLyrics {
                        Toggle("桌面歌词水平居中", isOn: $settings.desktopLyricsCentered)
                    }
                    Text("在屏幕上悬浮显示当前歌词，可拖动调整位置")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                #endif

                // On iPhone the sheet's openDestination closes settings first.
                StorageSpaceSections(model: storageModel, pendingDeletion: $pendingStorageDeletion,
                                     automaticLimitMB: automaticCacheLimitMB) {
                    openDestination(.downloaded)
                }

                #if os(macOS)
                Section("通用") {
                    NavigationLink(value: Destination.shortcuts) {
                        Label("快捷键", systemImage: "keyboard")
                    }
                    .pageFormNavigationRow()
                }
                #endif

                if account.provider == .netease && !ReadccHostBridge.isEmbedded {
                    SyncSettingsSection()
                }

                if !ReadccHostBridge.isEmbedded {
                    if usesMainColumn {
                        AboutSections(licensesRoute: Destination.openSourceLicenses, showsDisclaimer: $showsDisclaimer)
                    } else {
                        AboutSections(licensesRoute: SettingsPage.licenses, showsDisclaimer: $showsDisclaimer)
                    }
                }
            }
            .pageFormRows()
        }
        .pageFormStyle()
        .nativeTabBarScrolling()
        // Host presentations on the Form, never on a Section: iOS dismisses them when the List re-renders.
        .modifier(MusicAccountsPresenter(presentation: accountsPresentation))
        .storageSpaceHost(model: storageModel, pendingDeletion: $pendingStorageDeletion,
                          automaticLimitMB: $automaticCacheLimitMB)
        .sheet(isPresented: $showsDisclaimer) { DisclaimerView() }
        #if DEBUG
        .sheet(isPresented: $showsOnboardingPreview) {
            // Preview: never changes the accepted disclaimer version or completion state.
            OnboardingView(onDeclineDisclaimer: { showsOnboardingPreview = false },
                           onFinish: { showsOnboardingPreview = false })
        }
        #endif
        .navigationDestination(for: SettingsPage.self) { page in
            switch page {
            case .licenses:
                OpenSourceLicensesView()
            }
        }
    }

}
