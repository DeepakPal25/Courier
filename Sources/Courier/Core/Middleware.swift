import Foundation

public typealias HTTPHandler = @Sendable (URLRequest) async throws -> HTTPResponse

public protocol Middleware: Sendable {
    func intercept(_ request: URLRequest, next: @escaping HTTPHandler) async throws -> HTTPResponse
}

// Handy when you need a one-off middleware and don't want to define a whole type.
//
//   ClosureMiddleware { request, next in
//       var req = request
//       req.setValue("MyApp/2.0", forHTTPHeaderField: "User-Agent")
//       return try await next(req)
//   }
public struct ClosureMiddleware: Middleware {
    private let body: @Sendable (URLRequest, HTTPHandler) async throws -> HTTPResponse

    public init(_ body: @escaping @Sendable (URLRequest, HTTPHandler) async throws -> HTTPResponse) {
        self.body = body
    }

    public func intercept(_ request: URLRequest, next: @escaping HTTPHandler) async throws -> HTTPResponse {
        try await body(request, next)
    }
}
