import Foundation

// Routes through an injected closure so you can point it at os.Logger,
// a crash reporter, a test spy — whatever makes sense for the app:
//
//   let logger = Logger(subsystem: "com.example.app", category: "network")
//   LoggingMiddleware { logger.debug("\($0, privacy: .public)") }
public struct LoggingMiddleware: Middleware {
    public var redactedHeaders: Set<String>
    public var logsHeaders: Bool
    private let log: @Sendable (String) -> Void

    public init(
        logsHeaders: Bool = false,
        redactedHeaders: Set<String> = ["authorization", "cookie", "set-cookie", "x-api-key"],
        log: @escaping @Sendable (String) -> Void = { print($0) }
    ) {
        self.logsHeaders = logsHeaders
        self.redactedHeaders = Set(redactedHeaders.map { $0.lowercased() })
        self.log = log
    }

    public func intercept(_ request: URLRequest, next: HTTPHandler) async throws -> HTTPResponse {
        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? "<no url>"
        log("→ \(method) \(url)")

        if logsHeaders {
            for (field, value) in (request.allHTTPHeaderFields ?? [:]).sorted(by: { $0.key < $1.key }) {
                let display = redactedHeaders.contains(field.lowercased()) ? "<redacted>" : value
                log("   \(field): \(display)")
            }
        }

        let start = ContinuousClock.now
        do {
            let response = try await next(request)
            log("← \(response.statusCode) \(method) \(url) (\(milliseconds(since: start)) ms, \(response.body.count) bytes)")
            return response
        } catch {
            log("✗ \(method) \(url) (\(milliseconds(since: start)) ms): \(error)")
            throw error
        }
    }

    private func milliseconds(since start: ContinuousClock.Instant) -> Int {
        Int(((ContinuousClock.now - start).timeInterval * 1000).rounded())
    }
}
