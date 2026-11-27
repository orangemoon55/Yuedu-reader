import SwiftUI

struct PlaybackHandoffList: View {
    @ObservedObject private var sync = SyncService.shared
    @ObservedObject private var account = AccountStore.shared

    private var availableSessions: [SyncRecord<PlaybackCheckpoint>] {
        guard let accountID = account.authenticatedAccountID else { return [] }
        return sync.sessions.filter { $0.payload?.accountID == accountID }
    }

    var body: some View {
        if !availableSessions.isEmpty {
            VStack(spacing: Theme.Spacing.small) {
                ForEach(availableSessions) { record in
                    if let session = record.payload {
                        HStack(spacing: Theme.Spacing.small) {
                            Image(systemName: record.deviceSymbolName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 28, height: 28)
                                .background(Theme.accent.opacity(0.12), in: Circle())

                            VStack(alignment: .leading, spacing: Theme.Spacing.micro) {
                                Text(record.deviceName)
                                    .font(Theme.Typography.caption.weight(.medium))
                                    .lineLimit(1)
                                Text(session.currentTrack.name)
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 8)

                            Button {
                                Task {
                                    do { try await sync.resume(record) }
                                    catch is CancellationError { }
                                    catch { ToastCenter.shared.show(error.localizedDescription) }
                                }
                            } label: {
                                Text("接续")
                                    .font(Theme.Typography.caption.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                                    .padding(.horizontal, Theme.Spacing.control)
                                    .padding(.vertical, Theme.Spacing.tight)
                                    .background(Theme.accent.opacity(0.12), in: Capsule())
                                    .opacity(sync.resumingDeviceID == record.id ? 0 : 1)
                                    .overlay {
                                        if sync.resumingDeviceID == record.id { ProgressView().controlSize(.small) }
                                    }
                            }
                            .buttonStyle(.plain)
                            .disabled(sync.resumingDeviceID == record.id)
                        }
                        .padding(.horizontal, Theme.Spacing.control)
                        .padding(.vertical, Theme.Spacing.small)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
    }
}
