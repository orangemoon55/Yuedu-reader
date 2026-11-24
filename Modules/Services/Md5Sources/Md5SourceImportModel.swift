import Combine
import CryptoKit
import Foundation

/// Reads a `.js.md5` address the way the CatVod line does: the bundle sits beside the checksum
/// file (`index.js` + `index.js.md5`), the checksum is the bundle's MD5, and nothing is written
/// until the reader confirms. A plain `.js` address is accepted too, with no checksum to compare.
@MainActor
final class Md5SourceImportModel: ObservableObject {
    struct Preview: Equatable {
        let title: String
        let address: String
        let bundleAddress: String
        let checksum: String
        let data: Data
    }

    enum Phase: Equatable {
        case idle
        case loading
        case preview(Preview)
        case installing
        case failed(String)
        case done(Md5Source)
    }

    @Published var address = ""
    @Published var title = ""
    @Published private(set) var phase: Phase = .idle

    private let library: Md5SourceLibrary
    private let session: URLSession

    init(library: Md5SourceLibrary? = nil, session: URLSession? = nil) {
        self.library = library ?? .shared
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 90
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
    }

    var isLoading: Bool { phase == .loading || phase == .installing }

    var canFetch: Bool { !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading }

    func reset() {
        address = ""
        title = ""
        phase = .idle
    }

    func fetch() async {
        guard let target = Self.targets(for: address) else {
            phase = .failed(Md5SourceError.unsupportedAddress.message)
            return
        }
        phase = .loading
        do {
            let bundle = try await download(target.bundle)
            guard bundle.count <= Self.maximumBytes else {
                phase = .failed(Md5SourceError.tooLarge(bundle.count).message)
                return
            }
            var checksum = ""
            if let md5URL = target.checksum {
                let text = String(decoding: try await download(md5URL), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let hex = text.split(whereSeparator: { !$0.isHexDigit }).first.map(String.init) ?? ""
                guard hex.count == 32 else {
                    phase = .failed(Md5SourceError.checksumMismatch(expected: text.prefix(64).description,
                                                                    actual: "(no 32-hex checksum)").message)
                    return
                }
                checksum = hex
                let actual = Self.md5(of: bundle)
                guard actual == hex else {
                    phase = .failed(Md5SourceError.checksumMismatch(expected: hex, actual: actual).message)
                    return
                }
            }
            let suggested = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = suggested.isEmpty ? Self.suggestedTitle(for: target.bundle) : suggested
            phase = .preview(Preview(title: name, address: target.address, bundleAddress: target.bundle.absoluteString,
                                     checksum: checksum, data: bundle))
        } catch let error as Md5SourceError {
            phase = .failed(error.message)
        } catch {
            phase = .failed(Md5SourceError.download(error.localizedDescription).message)
        }
    }

    func commit() async {
        guard case .preview(let preview) = phase else { return }
        phase = .installing
        let id = Self.sha256(of: preview.data)
        let source = Md5Source(id: id, title: preview.title, address: preview.address,
                               bundleAddress: preview.bundleAddress, checksum: preview.checksum,
                               byteCount: preview.data.count, importedAt: .now)
        do {
            try library.install(bundle: preview.data, source: source)
            phase = .done(source)
        } catch let error as Md5SourceError {
            phase = .failed(error.message)
        } catch {
            phase = .failed(Md5SourceError.write(error.localizedDescription).message)
        }
    }

    // MARK: - Addresses

    struct Targets: Equatable {
        let address: String
        let bundle: URL
        let checksum: URL?
    }

    static func targets(for raw: String) -> Targets? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, var url = URL(string: text),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        let path = url.path.lowercased()
        if path.hasSuffix(".js.md5") {
            let md5 = url
            // ".md5" is four characters: dropping three leaves the trailing dot and the server 404s.
            url = URL(string: String(url.absoluteString.dropLast(4))) ?? url
            return Targets(address: text, bundle: url, checksum: md5)
        }
        if path.hasSuffix(".md5") {
            let md5 = url
            url = URL(string: String(url.absoluteString.dropLast(4))) ?? url
            return Targets(address: text, bundle: url, checksum: md5)
        }
        guard path.hasSuffix(".js") else { return nil }
        let companion = URL(string: url.absoluteString + ".md5")
        return Targets(address: text, bundle: url, checksum: companion)
    }

    static func suggestedTitle(for url: URL) -> String {
        let host = url.host ?? "MD5 源"
        let last = url.lastPathComponent.replacingOccurrences(of: ".js", with: "")
        return last.isEmpty || last == "index" ? host : "\(host)/\(last)"
    }

    // MARK: - Network

    private func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Readcc/1.0 (iOS; CatVod bundle reader)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/javascript, application/octet-stream, text/plain, */*", forHTTPHeaderField: "Accept")
        if let user = url.user, let password = url.password {
            let token = Data("\(user):\(password)".utf8).base64EncodedString()
            request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Md5SourceError.download("HTTP \(http.statusCode)")
        }
        return data
    }

    // MARK: - Digests

    static let maximumBytes = 64 * 1024 * 1024

    static func md5(of data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
