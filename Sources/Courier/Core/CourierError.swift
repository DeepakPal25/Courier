import Foundation

public enum CourierError: Error, Sendable {
    case invalidURL(String)
    case unacceptableStatus(code: Int, body: Data)
    // underlying error + the raw bytes so callers can log or inspect
    case decoding(underlying: any Error, body: Data)
    case transport(any Error)
    case nonHTTPResponse
}

extension CourierError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL(let path):
            return "Couldn't build a valid URL for '\(path)'."
        case .unacceptableStatus(let code, _):
            return "Server replied with status \(code)."
        case .decoding(let err, _):
            return "Couldn't decode response: \(err.localizedDescription)"
        case .transport(let err):
            return "Request failed: \(err.localizedDescription)"
        case .nonHTTPResponse:
            return "Got back something that wasn't an HTTP response."
        }
    }
}
