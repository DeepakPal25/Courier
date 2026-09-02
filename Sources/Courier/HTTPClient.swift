import Foundation

// Basic usage:
//
//   let client = HTTPClient(
//       baseURL: URL(string: "https://api.example.com/v1")!,
//       middleware: [
//           LoggingMiddleware(),
//           DeduplicationMiddleware(),
//           RetryMiddleware(policy: .default),
//           AuthMiddleware(tokens: tokenRefresher),
//       ]
//   )
//
//   let user = try await client.send(Request<User>.get("users/42"))
//
// Middleware runs in array order on the way out and in reverse on the way back,
// so the first item is the outermost wrapper.
public final class HTTPClient: Sendable {
    public let baseURL: URL
    private let defaultHeaders: [String: String]
    private let decoder: any ResponseDecoder
    private let handler: HTTPHandler

    public init(
        baseURL: URL,
        transport: any HTTPTransport = URLSessionTransport(),
        middleware: [any Middleware] = [],
        decoder: any ResponseDecoder = JSONResponseDecoder(),
        defaultHeaders: [String: String] = [:]
    ) {
        self.baseURL = baseURL
        self.defaultHeaders = defaultHeaders
        self.decoder = decoder

        var handler: HTTPHandler = { request in try await transport.send(request) }
        for layer in middleware.reversed() {
            let next = handler
            handler = { request in try await layer.intercept(request, next: next) }
        }
        self.handler = handler
    }

    public func send<Response>(_ request: Request<Response>) async throws -> Response {
        let response = try await sendRaw(request)

        guard response.isSuccess else {
            throw CourierError.unacceptableStatus(code: response.statusCode, body: response.body)
        }
        if let empty = EmptyResponse() as? Response {
            return empty
        }
        do {
            return try decoder.decode(Response.self, from: response.body)
        } catch {
            throw CourierError.decoding(underlying: error, body: response.body)
        }
    }

    // Sends through the middleware chain without status validation or decoding.
    // Useful when you need the raw response (e.g. checking a custom header before deciding what to do).
    public func sendRaw<Response>(_ request: Request<Response>) async throws -> HTTPResponse {
        let urlRequest = try request.makeURLRequest(baseURL: baseURL, defaultHeaders: defaultHeaders)
        do {
            return try await handler(urlRequest)
        } catch let error as CourierError {
            throw error
        } catch let error as CancellationError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw CourierError.transport(error)
        }
    }
}
