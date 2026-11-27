import Foundation
import os

/// A shared sign-in as it sits in the sync folder. The folder lives in the
/// user's own iCloud Drive, which only their Apple Account can read, so the
/// session travels with the rest of sync without a separate passphrase.
struct SyncedLogin: Codable, Equatable {
    let accountID: Int
    let nickname: String
    let cookies: [String: String]

    init(accountID: Int, nickname: String, cookies: [String: String]) {
        self.accountID = accountID
        self.nickname = nickname
        self.cookies = cookies
    }

    private enum CodingKeys: String, CodingKey { case accountID, nickname, cookies }

    /// Offers written by builds that sealed the cookies with a sync passphrase
    /// decode without cookies and are rejected by `validate`, not the folder.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accountID = try c.decode(Int.self, forKey: .accountID)
        nickname = try c.decode(String.self, forKey: .nickname)
        cookies = try c.decodeIfPresent([String: String].self, forKey: .cookies) ?? [:]
    }

    func validate() throws {
        guard accountID > 0, cookies["MUSIC_U"]?.isEmpty == false else { throw SyncError.invalidRecord }
    }

    private static let log = Logger(subsystem: "wow.caicai.coda", category: "login-sync")

    static func availableAccounts(in records: [SyncRecord<Self>], excluding deviceID: UUID) -> [SyncRecord<Self>] {
        // Resolve each device's deletion marker before collapsing duplicate accounts.
        let latest = Dictionary(grouping: records, by: \.id).values.compactMap {
            $0.max { $0.revision < $1.revision }
        }.filter { record in
            guard record.id != deviceID else { return false }
            do {
                guard let login = record.payload else { return false }
                try login.validate()
                return true
            } catch {
                // Never resurrect an older login when the latest record is invalid.
                log.error("Rejected login record for device \(record.id.uuidString, privacy: .public)")
                return false
            }
        }
        return Dictionary(grouping: latest, by: { $0.payload?.accountID }).values.compactMap {
            $0.max { $0.revision < $1.revision }
        }.sorted { $0.revision > $1.revision }
    }
}
