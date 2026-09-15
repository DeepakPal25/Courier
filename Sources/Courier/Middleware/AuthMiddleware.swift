import Foundation

// Manages an access token and refreshes it when needed.
//
// Classic bug this prevents: ten requests fire simultaneously, all get a 401,
// all ten race to refresh — which usually invalidates tokens mid-flight.
// Because this is an actor, at most one refresh is ever in flight. If your
// token was already replaced by the time you call refresh(replacing:), you
// just get the new one back with no extra network call.
public actor TokenRefresher {
    private var token: String?
    private var refreshTask: Task<String, any Error>?
    private let fetchToken: @Sendable () async throws -> String

    /// - Parameters:
    ///   - initialToken: Pass a token restored from the Keychain here, if you have one.
    ///   - refresh: Called to obtain a new access token (e.g. hit your /refresh endpoint).
    public init(initialToken: String? = nil, refresh: @escaping @Sendable () async throws -> String) {
        self.token = initialToken
        self.fetchToken = refresh
    }

    public func validToken() async throws -> String {
        if let refreshTask { return try await refreshTask.value }
        if let token { return token }
        return try await startRefresh()
    }

    public func refresh(replacing staleToken: String) async throws -> String {
        if let refreshTask { return try await refreshTask.value }
        // someone else already refreshed while we were waiting
        if let token, token != staleToken { return token }
        return try await startRefresh()
    }

    public func invalidate() {
        token = nil
    }

    private func startRefresh() async throws -> String {
        let fetchToken = self.fetchToken
        let task = Task { try await fetchToken() }
        refreshTask = task
        defer { refreshTask = nil }
        let newToken = try await task.value
        token = newToken
        return newToken
    }
}

// Stamps each request with an Authorization header and retries once on 401.
// The single retry prevents an endpoint that keeps returning 401 from causing
// a refresh loop.
public struct AuthMiddleware: Middleware {
    private let tokens: TokenRefresher
    private let scheme: String

    public init(tokens: TokenRefresher, scheme: String = "Bearer") {
        self.tokens = tokens
        self.scheme = scheme
    }

    public func intercept(_ request: URLRequest, next: @escaping HTTPHandler) async throws -> HTTPResponse {
        let token = try await tokens.validToken()
        let response = try await next(authorize(request, with: token))
        guard response.statusCode == 401 else { return response }

        let freshToken = try await tokens.refresh(replacing: token)
        return try await next(authorize(request, with: freshToken))
    }

    private func authorize(_ request: URLRequest, with token: String) -> URLRequest {
        var request = request
        request.setValue("\(scheme) \(token)", forHTTPHeaderField: "Authorization")
        return request
    }
}
