import Courier
import Foundation

// In-memory transport for tests. Responses come from a FIFO queue first;
// once the queue is empty it falls back to the responder closure.
// All requests are recorded so you can assert on what was sent.
//
//   let transport = MockTransport()
//   await transport.enqueue(HTTPResponse(statusCode: 503), try .json(user))
//   let client = HTTPClient(baseURL: baseURL, transport: transport)
public actor MockTransport: HTTPTransport {
    public typealias Responder = @Sendable (URLRequest) async throws -> HTTPResponse

    public private(set) var requests: [URLRequest] = []
    private var queue: [Result<HTTPResponse, any Error>] = []
    private let responder: Responder

    public init(responder: @escaping Responder = { request in
        throw MockTransportError.noResponseStubbed(request.url)
    }) {
        self.responder = responder
    }

    public func enqueue(_ responses: HTTPResponse...) {
        queue.append(contentsOf: responses.map { .success($0) })
    }

    public func enqueue(error: any Error) {
        queue.append(.failure(error))
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        if !queue.isEmpty {
            return try queue.removeFirst().get()
        }
        return try await responder(request)
    }
}

public enum MockTransportError: Error, Sendable {
    case noResponseStubbed(URL?)
}

extension HTTPResponse {
    public static func json(
        _ value: some Encodable,
        status: Int = 200,
        headers: [String: String] = [:],
        encoder: JSONEncoder = JSONEncoder()
    ) throws -> HTTPResponse {
        HTTPResponse(
            statusCode: status,
            headers: headers.merging(["Content-Type": "application/json"]) { current, _ in current },
            body: try encoder.encode(value)
        )
    }
}
