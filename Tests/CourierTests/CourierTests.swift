import Courier
import CourierTesting
import Foundation
import Testing

struct User: Codable, Sendable, Equatable {
    let id: Int
    let name: String
}

let baseURL = URL(string: "https://api.example.com/v1")!
let ada = User(id: 1, name: "Ada")

actor Recorder<Value: Sendable> {
    private(set) var values: [Value] = []
    func record(_ value: Value) { values.append(value) }
}

// LoggingMiddleware takes a synchronous closure, so we need a thread-safe
// container to collect lines from test assertions.
final class LockedLines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) {
        lock.withLock { lines.append(line) }
    }

    var joined: String {
        lock.withLock { lines.joined(separator: "\n") }
    }
}

// MARK: - HTTPClient

@Suite("HTTPClient")
struct HTTPClientTests {
    @Test("Builds the URL, merges headers and decodes the body")
    func decodesAndBuildsRequest() async throws {
        let transport = MockTransport { _ in try .json(ada) }
        let client = HTTPClient(
            baseURL: baseURL,
            transport: transport,
            defaultHeaders: ["Accept": "application/json", "X-Client": "default"]
        )

        let user = try await client.send(
            Request<User>.get("/users/1", query: [URLQueryItem(name: "q", value: "a+b c")], headers: ["X-Client": "override"])
        )

        #expect(user == ada)
        let sent = try #require(await transport.requests.first)
        #expect(sent.url?.absoluteString == "https://api.example.com/v1/users/1?q=a%2Bb%20c")
        #expect(sent.httpMethod == "GET")
        #expect(sent.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(sent.value(forHTTPHeaderField: "X-Client") == "override")
    }

    @Test("Encodes JSON bodies for POST")
    func encodesJSONBody() async throws {
        let transport = MockTransport { request in
            let body = try JSONDecoder().decode(User.self, from: request.httpBody ?? Data())
            return try .json(body, status: 201)
        }
        let client = HTTPClient(baseURL: baseURL, transport: transport)

        let created: User = try await client.send(.post("users", json: ada))

        #expect(created == ada)
        let sent = try #require(await transport.requests.first)
        #expect(sent.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("Non-2xx responses throw unacceptableStatus with the body")
    func throwsOnBadStatus() async throws {
        let transport = MockTransport { _ in HTTPResponse(statusCode: 404, body: Data("missing".utf8)) }
        let client = HTTPClient(baseURL: baseURL, transport: transport)

        do {
            _ = try await client.send(Request<User>.get("users/999"))
            Issue.record("Expected an error")
        } catch CourierError.unacceptableStatus(let code, let body) {
            #expect(code == 404)
            #expect(String(decoding: body, as: UTF8.self) == "missing")
        }
    }

    @Test("Malformed bodies throw a decoding error")
    func throwsOnDecodingFailure() async throws {
        let transport = MockTransport { _ in HTTPResponse(statusCode: 200, body: Data("{}".utf8)) }
        let client = HTTPClient(baseURL: baseURL, transport: transport)

        await #expect {
            _ = try await client.send(Request<User>.get("users/1"))
        } throws: { error in
            guard case CourierError.decoding = error else { return false }
            return true
        }
    }

    @Test("EmptyResponse succeeds without a body")
    func emptyResponse() async throws {
        let transport = MockTransport { _ in HTTPResponse(statusCode: 204) }
        let client = HTTPClient(baseURL: baseURL, transport: transport)

        let result = try await client.send(Request<EmptyResponse>.delete("users/1"))

        #expect(result == EmptyResponse())
    }

    @Test("Middleware runs in declaration order")
    func middlewareOrder() async throws {
        let order = Recorder<String>()
        func tracer(_ name: String) -> ClosureMiddleware {
            ClosureMiddleware { request, next in
                await order.record("\(name) in")
                let response = try await next(request)
                await order.record("\(name) out")
                return response
            }
        }
        let client = HTTPClient(
            baseURL: baseURL,
            transport: MockTransport { _ in try .json(ada) },
            middleware: [tracer("A"), tracer("B")]
        )

        _ = try await client.send(Request<User>.get("users/1"))

        #expect(await order.values == ["A in", "B in", "B out", "A out"])
    }
}

// MARK: - Retry

@Suite("RetryMiddleware")
struct RetryTests {
    let fixedBackoff = Backoff.exponential(base: .milliseconds(100), multiplier: 2, maxDelay: .seconds(5), jitter: false)

    @Test("Retries transient status codes with exponential backoff")
    func retriesWithBackoff() async throws {
        let transport = MockTransport()
        let success = try HTTPResponse.json(ada)
        await transport.enqueue(HTTPResponse(statusCode: 503), HTTPResponse(statusCode: 502), success)
        let sleeps = Recorder<Duration>()
        let client = HTTPClient(
            baseURL: baseURL,
            transport: transport,
            middleware: [RetryMiddleware(policy: RetryPolicy(maxAttempts: 3, backoff: fixedBackoff)) { await sleeps.record($0) }]
        )

        let user = try await client.send(Request<User>.get("users/1"))

        #expect(user == ada)
        #expect(await transport.requests.count == 3)
        #expect(await sleeps.values == [.milliseconds(100), .milliseconds(200)])
    }

    @Test("Honours Retry-After")
    func honoursRetryAfter() async throws {
        let transport = MockTransport()
        let success = try HTTPResponse.json(ada)
        await transport.enqueue(HTTPResponse(statusCode: 429, headers: ["retry-after": "2"]), success)
        let sleeps = Recorder<Duration>()
        let client = HTTPClient(
            baseURL: baseURL,
            transport: transport,
            middleware: [RetryMiddleware(policy: RetryPolicy(backoff: fixedBackoff)) { await sleeps.record($0) }]
        )

        _ = try await client.send(Request<User>.get("users/1"))

        #expect(await sleeps.values == [.seconds(2)])
    }

    @Test("Gives up after maxAttempts and surfaces the last status")
    func givesUp() async throws {
        let transport = MockTransport { _ in HTTPResponse(statusCode: 500) }
        let client = HTTPClient(
            baseURL: baseURL,
            transport: transport,
            middleware: [RetryMiddleware(policy: RetryPolicy(maxAttempts: 4, backoff: .none)) { _ in }]
        )

        await #expect(throws: CourierError.self) {
            _ = try await client.send(Request<User>.get("users/1"))
        }
        #expect(await transport.requests.count == 4)
    }

    @Test("Does not retry non-idempotent methods")
    func skipsPost() async throws {
        let transport = MockTransport { _ in HTTPResponse(statusCode: 503) }
        let client = HTTPClient(
            baseURL: baseURL,
            transport: transport,
            middleware: [RetryMiddleware(policy: RetryPolicy(backoff: .none)) { _ in }]
        )

        await #expect(throws: CourierError.self) {
            let _: User = try await client.send(.post("users", json: ada))
        }
        #expect(await transport.requests.count == 1)
    }

    @Test("Retries retryable URLErrors")
    func retriesURLErrors() async throws {
        let transport = MockTransport()
        await transport.enqueue(error: URLError(.networkConnectionLost))
        await transport.enqueue(try HTTPResponse.json(ada))
        let client = HTTPClient(
            baseURL: baseURL,
            transport: transport,
            middleware: [RetryMiddleware(policy: RetryPolicy(backoff: .none)) { _ in }]
        )

        let user = try await client.send(Request<User>.get("users/1"))

        #expect(user == ada)
        #expect(await transport.requests.count == 2)
    }

    @Test("Jittered delays stay within the cap")
    func jitterBounds() {
        let backoff = Backoff.exponential(base: .seconds(1), multiplier: 3, maxDelay: .seconds(5), jitter: true)
        for attempt in 1...10 {
            let delay = backoff.delay(afterAttempt: attempt)
            #expect(delay >= .zero && delay <= .seconds(5))
        }
    }
}

// MARK: - Deduplication

@Suite("DeduplicationMiddleware")
struct DeduplicationTests {
    @Test("Concurrent identical GETs share one network call")
    func coalescesGets() async throws {
        let transport = MockTransport { _ in
            try await Task.sleep(for: .milliseconds(200))
            return try .json(ada)
        }
        let client = HTTPClient(baseURL: baseURL, transport: transport, middleware: [DeduplicationMiddleware()])

        try await withThrowingTaskGroup(of: User.self) { group in
            for _ in 0..<10 {
                group.addTask { try await client.send(Request<User>.get("users/1")) }
            }
            for try await user in group {
                #expect(user == ada)
            }
        }

        #expect(await transport.requests.count == 1)
    }

    @Test("Different URLs are not coalesced")
    func distinctRequests() async throws {
        let transport = MockTransport { _ in try .json(ada) }
        let client = HTTPClient(baseURL: baseURL, transport: transport, middleware: [DeduplicationMiddleware()])

        async let first = client.send(Request<User>.get("users/1"))
        async let second = client.send(Request<User>.get("users/2"))
        _ = try await (first, second)

        #expect(await transport.requests.count == 2)
    }
}

// MARK: - Auth

@Suite("AuthMiddleware")
struct AuthTests {
    @Test("Attaches the bearer token")
    func attachesToken() async throws {
        let transport = MockTransport { _ in try .json(ada) }
        let tokens = TokenRefresher(initialToken: "abc") { "unused" }
        let client = HTTPClient(baseURL: baseURL, transport: transport, middleware: [AuthMiddleware(tokens: tokens)])

        _ = try await client.send(Request<User>.get("me"))

        let sent = try #require(await transport.requests.first)
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
    }

    @Test("Concurrent 401s trigger exactly one refresh")
    func coalescesRefresh() async throws {
        let refreshCount = Recorder<Void>()
        let tokens = TokenRefresher(initialToken: "stale") {
            await refreshCount.record(())
            try await Task.sleep(for: .milliseconds(100))
            return "fresh"
        }
        let transport = MockTransport { request in
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer fresh" {
                return try .json(ada)
            }
            return HTTPResponse(statusCode: 401)
        }
        let client = HTTPClient(baseURL: baseURL, transport: transport, middleware: [AuthMiddleware(tokens: tokens)])

        try await withThrowingTaskGroup(of: User.self) { group in
            for _ in 0..<8 {
                group.addTask { try await client.send(Request<User>.get("me")) }
            }
            for try await user in group {
                #expect(user == ada)
            }
        }

        #expect(await refreshCount.values.count == 1)
        #expect(try await tokens.validToken() == "fresh")
    }

    @Test("A persistent 401 is surfaced instead of looping")
    func noRefreshLoop() async throws {
        let transport = MockTransport { _ in HTTPResponse(statusCode: 401) }
        let tokens = TokenRefresher(initialToken: "a") { UUID().uuidString }
        let client = HTTPClient(baseURL: baseURL, transport: transport, middleware: [AuthMiddleware(tokens: tokens)])

        await #expect(throws: CourierError.self) {
            _ = try await client.send(Request<User>.get("me"))
        }
        #expect(await transport.requests.count == 2)
    }
}

// MARK: - Logging

@Suite("LoggingMiddleware")
struct LoggingTests {
    @Test("Redacts sensitive headers")
    func redacts() async throws {
        let lines = LockedLines()
        let logger = LoggingMiddleware(logsHeaders: true) { lines.append($0) }
        let handler: HTTPHandler = { _ in HTTPResponse(statusCode: 200) }
        var request = URLRequest(url: baseURL)
        request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")

        _ = try await logger.intercept(request, next: handler)

        let output = lines.joined
        #expect(output.contains("<redacted>"))
        #expect(!output.contains("secret"))
    }
}
