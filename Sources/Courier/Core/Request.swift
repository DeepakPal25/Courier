import Foundation

// The Response type lives on the request itself so call sites never need to
// pass a type parameter separately and can't accidentally decode into the wrong model:
//
//   let user = try await client.send(Request<User>.get("users/42"))
public struct Request<Response: Decodable & Sendable>: Sendable {
    public var method: HTTPMethod
    public var path: String
    public var queryItems: [URLQueryItem]
    public var headers: [String: String]
    public var body: Data?
    public var timeout: Duration?

    public init(
        _ method: HTTPMethod = .get,
        _ path: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: Duration? = nil
    ) {
        self.method = method
        self.path = path
        self.queryItems = query
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}

// MARK: - Convenience

extension Request {
    public static func get(_ path: String, query: [URLQueryItem] = [], headers: [String: String] = [:]) -> Request {
        Request(.get, path, query: query, headers: headers)
    }

    public static func delete(_ path: String, query: [URLQueryItem] = [], headers: [String: String] = [:]) -> Request {
        Request(.delete, path, query: query, headers: headers)
    }

    public static func post(_ path: String, json body: some Encodable, encoder: JSONEncoder = JSONEncoder()) throws -> Request {
        try Request.jsonBody(.post, path, body, encoder)
    }

    public static func put(_ path: String, json body: some Encodable, encoder: JSONEncoder = JSONEncoder()) throws -> Request {
        try Request.jsonBody(.put, path, body, encoder)
    }

    public static func patch(_ path: String, json body: some Encodable, encoder: JSONEncoder = JSONEncoder()) throws -> Request {
        try Request.jsonBody(.patch, path, body, encoder)
    }

    private static func jsonBody(_ method: HTTPMethod, _ path: String, _ body: some Encodable, _ encoder: JSONEncoder) throws -> Request {
        Request(method, path, headers: ["Content-Type": "application/json"], body: try encoder.encode(body))
    }
}

// MARK: - URLRequest construction

extension Request {
    func makeURLRequest(baseURL: URL, defaultHeaders: [String: String]) throws -> URLRequest {
        let trimmedPath = path.drop { $0 == "/" }
        var url = trimmedPath.isEmpty ? baseURL : baseURL.appending(path: String(trimmedPath))

        if !queryItems.isEmpty {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw CourierError.invalidURL(path)
            }
            components.queryItems = (components.queryItems ?? []) + queryItems
            // URLComponents leaves "+" unescaped; most servers treat it as a space,
            // so force-encode it to keep the literal plus sign.
            components.percentEncodedQuery = components.percentEncodedQuery?
                .replacingOccurrences(of: "+", with: "%2B")
            guard let resolved = components.url else { throw CourierError.invalidURL(path) }
            url = resolved
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = body
        for (field, value) in defaultHeaders.merging(headers, uniquingKeysWith: { _, override in override }) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        if let timeout {
            request.timeoutInterval = timeout.timeInterval
        }
        return request
    }
}

/// Use as the response type when an endpoint returns no body (204, etc.).
public struct EmptyResponse: Decodable, Sendable, Equatable {
    public init() {}
}

extension Duration {
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}
