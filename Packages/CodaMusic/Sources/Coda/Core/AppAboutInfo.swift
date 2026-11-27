import Foundation

/// Product facts shown on the About page. Values come from the bundle's
/// Info.plist, which the build fills from `Config/AppIdentity.xcconfig`.
struct AppAboutInfo {
    let name: String
    let version: String
    let build: String
    let commit: String?
    let repository: String
    let developer: String

    init(bundle: Bundle = .main, repository: String = CodaIdentity.releaseRepository) {
        let info = bundle.infoDictionary ?? [:]
        func value(_ key: String) -> String? {
            (info[key] as? String).map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        self.repository = repository
        name = value("CFBundleDisplayName") ?? value("CFBundleName") ?? Self.repositoryName(repository)
        version = value("CFBundleShortVersionString") ?? "dev"
        build = value("CFBundleVersion") ?? "—"
        commit = value("CodaGitCommit").flatMap { $0 == "unknown" ? nil : $0 }
        developer = value("CodaDeveloperName") ?? Self.repositoryOwner(repository)
    }

    var repositoryURL: URL? { URL(string: "https://github.com/\(repository)") }
    var issuesURL: URL? { repositoryURL?.appendingPathComponent("issues") }
    var releasesURL: URL? { repositoryURL?.appendingPathComponent("releases") }
    /// The project site is the repository's GitHub Pages address.
    var websiteURL: URL? { Self.pagesURL(for: repository) }

    func fileURL(_ path: String) -> URL? { URL(string: "https://github.com/\(repository)/blob/main/\(path)") }

    static func pagesURL(for repository: String) -> URL? {
        let parts = repository.split(separator: "/")
        guard parts.count == 2 else { return nil }
        return URL(string: "https://\(parts[0].lowercased()).github.io/\(parts[1])/")
    }

    /// `host/path` without scheme or trailing slash, for compact display.
    static func displayAddress(_ url: URL) -> String {
        var text = (url.host ?? "") + url.path
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    private static func repositoryOwner(_ repository: String) -> String {
        repository.split(separator: "/").first.map(String.init) ?? repository
    }

    private static func repositoryName(_ repository: String) -> String {
        repository.split(separator: "/").last.map(String.init) ?? repository
    }
}

/// Bundled legal texts. These paths are resolved only inside CodaCore's
/// SwiftPM resource bundle; never fall back to the host app's root LICENSE.
enum BundledLegalDocument: String, CaseIterable, Identifiable {
    case license = "LICENSE"
    case copying = "COPYING"
    case thirdPartyNotices = "ThirdPartyNotices/README.md"

    var id: String { rawValue }

    var bundleURL: URL? {
        guard let resourceRoot = Bundle.module.resourceURL else { return nil }
        let url = rawValue.split(separator: "/").reduce(resourceRoot.appendingPathComponent("CodaLegal", isDirectory: true)) {
            $0.appendingPathComponent(String($1))
        }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var text: String? { bundleURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } }
}

struct ThirdPartyNoticeEntry: Equatable {
    let name: String
    let url: URL?
    let license: String?
}

struct ThirdPartyNoticeGroup: Equatable {
    let title: String
    let entries: [ThirdPartyNoticeEntry]
}

/// Reads the project tables in `ThirdPartyNotices/README.md`, so the in-app
/// acknowledgements never drift from the maintained index.
enum ThirdPartyNotices {
    static func parse(_ markdown: String) -> [ThirdPartyNoticeGroup] {
        var groups: [ThirdPartyNoticeGroup] = []
        var title: String?
        var entries: [ThirdPartyNoticeEntry] = []
        var licenseColumn: Int?
        var sawHeader = false

        func flush() {
            if let title, !entries.isEmpty { groups.append(.init(title: title, entries: entries)) }
            entries = []
            licenseColumn = nil
            sawHeader = false
        }

        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                flush()
                title = stripNumbering(String(line.dropFirst(3)))
                continue
            }
            guard title != nil, line.hasPrefix("|") else { continue }
            let cells = splitRow(line)
            if !sawHeader {
                sawHeader = true
                licenseColumn = cells.firstIndex(of: "许可证")
                continue
            }
            if cells.allSatisfy({ $0.allSatisfy { $0 == "-" || $0 == ":" || $0 == " " } }) { continue }
            guard let first = cells.first, !first.isEmpty else { continue }
            let link = firstLink(in: first)
            let name = link?.text ?? stripLinks(first)
            let license = licenseColumn.flatMap { $0 < cells.count ? cleanLicense(cells[$0]) : nil }
            entries.append(.init(name: name, url: link?.url, license: license))
        }
        flush()
        return groups
    }

    private static func splitRow(_ line: String) -> [String] {
        var body = Substring(line)
        if body.hasPrefix("|") { body = body.dropFirst() }
        if body.hasSuffix("|") { body = body.dropLast() }
        return body.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func stripNumbering(_ heading: String) -> String {
        guard let dot = heading.firstIndex(of: "."), heading[..<dot].allSatisfy(\.isNumber) else { return heading }
        return heading[heading.index(after: dot)...].trimmingCharacters(in: .whitespaces)
    }

    private static let linkPattern = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#)

    private static func firstLink(in text: String) -> (text: String, url: URL?)? {
        let ns = text as NSString
        guard let match = linkPattern.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let target = ns.substring(with: match.range(at: 2))
        let url = target.hasPrefix("http") ? URL(string: target) : nil
        return (ns.substring(with: match.range(at: 1)), url)
    }

    private static func stripLinks(_ text: String) -> String {
        let ns = text as NSString
        return linkPattern.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "$1")
            .replacingOccurrences(of: "`", with: "")
    }

    private static func cleanLicense(_ cell: String) -> String? {
        var text = stripLinks(cell)
        if let cut = text.firstIndex(where: { $0 == "（" || $0 == "(" }) { text = String(text[..<cut]) }
        text = text.trimmingCharacters(in: .whitespaces)
        if text.isEmpty || text == "—" || text == "-" || text.hasPrefix("见") { return nil }
        return text
    }
}
