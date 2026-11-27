// Adapted from XIaodou0416/Beans-Music (MIT); see ThirdPartyNotices/Beans-Music.md.
import Foundation
enum ProviderRequestError: LocalizedError {
    case network
    case httpStatus(Int, String)
    case decoding(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .network: return "网络连接失败，请检查网络"
        case .httpStatus(let code, let snippet):
            return snippet.isEmpty ? "服务器响应异常（\(code)）" : "服务器响应异常（\(code)）\(snippet)"
        case .decoding:
            return "音乐平台响应格式异常，请稍后重试"
        case .unknown(let message): return message
        }
    }
}
