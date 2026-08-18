// Using a struct here so you can pass custom verbs like "PROPFIND" without
// needing a library change.
public struct HTTPMethod: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.uppercased()
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public static let get: HTTPMethod = "GET"
    public static let head: HTTPMethod = "HEAD"
    public static let post: HTTPMethod = "POST"
    public static let put: HTTPMethod = "PUT"
    public static let patch: HTTPMethod = "PATCH"
    public static let delete: HTTPMethod = "DELETE"
    public static let options: HTTPMethod = "OPTIONS"

    // RFC 9110 — safe to retry these
    public static let idempotent: Set<HTTPMethod> = [.get, .head, .put, .delete, .options]
}
