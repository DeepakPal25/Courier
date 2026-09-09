import Foundation

// When multiple screens request the same resource at once (common with SwiftUI .task),
// only the first call hits the network. Everyone else awaits that same Task.
//
// "Identical" means equal URLRequests — same URL, headers, and body.
// The entry is removed as soon as the request completes, so this isn't a cache.
//
// Note: the shared Task keeps running to completion even if all waiters are cancelled.
// Each individual caller still sees its own cancellation when it resumes.
public actor DeduplicationMiddleware: Middleware {
    private var inFlight: [URLRequest: Task<HTTPResponse, any Error>] = [:]
    private let methods: Set<HTTPMethod>

    public init(methods: Set<HTTPMethod> = [.get, .head]) {
        self.methods = methods
    }

    public func intercept(_ request: URLRequest, next: HTTPHandler) async throws -> HTTPResponse {
        guard methods.contains(HTTPMethod(rawValue: request.httpMethod ?? "GET")) else {
            return try await next(request)
        }

        if let existing = inFlight[request] {
            return try await existing.value
        }

        let task = Task { try await next(request) }
        inFlight[request] = task
        defer { inFlight[request] = nil }
        return try await task.value
    }

    // Mainly useful in tests to assert how many requests actually went out.
    public var inFlightCount: Int { inFlight.count }
}
