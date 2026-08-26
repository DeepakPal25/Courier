import Foundation

// Value-type snapshot of a response. We convert at the transport boundary so
// nothing above it ever has to think about reference-type thread safety.
public struct HTTPResponse: Sendable, Equatable {
    public var statusCode: Int
    public var headers: [String: String]
    public var body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    // case-insensitive per RFC 9110
    public subscript(header name: String) -> String? {
        if let exact = headers[name] { return exact }
        let lowered = name.lowercased()
        return headers.first { $0.key.lowercased() == lowered }?.value
    }

    public var isSuccess: Bool { (200..<300).contains(statusCode) }

    public var retryAfter: Duration? {
        guard let value = self[header: "Retry-After"],
              let seconds = Double(value.trimmingCharacters(in: .whitespaces)),
              seconds >= 0
        else { return nil }
        return .seconds(seconds)
    }
}
