import Foundation

public enum Backoff: Sendable, Equatable {
    case none
    case constant(Duration)
    // base * multiplier^(attempt-1), capped at maxDelay.
    // With jitter on, the actual delay is drawn from 0...computed ("full jitter"),
    // which keeps a thundering herd from all hitting the server at the same instant.
    case exponential(base: Duration, multiplier: Double = 2, maxDelay: Duration, jitter: Bool = true)

    public func delay(afterAttempt attempt: Int) -> Duration {
        switch self {
        case .none:
            return .zero
        case .constant(let delay):
            return delay
        case .exponential(let base, let multiplier, let maxDelay, let jitter):
            let raw = base.timeInterval * pow(multiplier, Double(max(attempt - 1, 0)))
            let capped = min(raw, maxDelay.timeInterval)
            let seconds = jitter ? Double.random(in: 0...capped) : capped
            return .milliseconds(Int((seconds * 1000).rounded()))
        }
    }
}

public struct RetryPolicy: Sendable {
    // Total attempts including the first; 1 = no retries
    public var maxAttempts: Int
    public var backoff: Backoff
    public var retryableStatusCodes: Set<Int>
    // POST and PATCH are excluded by default — retrying those can cause side effects
    // (double-charges, duplicate records, etc.)
    public var retryableMethods: Set<HTTPMethod>
    public var retryableURLErrors: Set<URLError.Code>
    public var respectsRetryAfter: Bool
    public var maxRetryAfter: Duration

    public init(
        maxAttempts: Int = 3,
        backoff: Backoff = .exponential(base: .milliseconds(300), maxDelay: .seconds(10)),
        retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504],
        retryableMethods: Set<HTTPMethod> = HTTPMethod.idempotent,
        retryableURLErrors: Set<URLError.Code> = [
            .timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed, .notConnectedToInternet,
        ],
        respectsRetryAfter: Bool = true,
        maxRetryAfter: Duration = .seconds(60)
    ) {
        self.maxAttempts = max(1, maxAttempts)
        self.backoff = backoff
        self.retryableStatusCodes = retryableStatusCodes
        self.retryableMethods = retryableMethods
        self.retryableURLErrors = retryableURLErrors
        self.respectsRetryAfter = respectsRetryAfter
        self.maxRetryAfter = maxRetryAfter
    }

    public static let `default` = RetryPolicy()
    public static let never = RetryPolicy(maxAttempts: 1)

    func canRetry(_ method: HTTPMethod) -> Bool {
        retryableMethods.contains(method)
    }

    func shouldRetry(_ response: HTTPResponse) -> Bool {
        retryableStatusCodes.contains(response.statusCode)
    }

    func shouldRetry(_ error: any Error) -> Bool {
        if error is CancellationError { return false }
        guard let urlError = error as? URLError else { return false }
        return retryableURLErrors.contains(urlError.code)
    }

    func delay(afterAttempt attempt: Int, response: HTTPResponse? = nil) -> Duration {
        if respectsRetryAfter, let requested = response?.retryAfter {
            return min(requested, maxRetryAfter)
        }
        return backoff.delay(afterAttempt: attempt)
    }
}

// Cancellation-aware: if the calling task is cancelled during the backoff sleep,
// the error propagates and no further attempts are made.
public struct RetryMiddleware: Middleware {
    public let policy: RetryPolicy
    private let sleep: @Sendable (Duration) async throws -> Void

    public init(
        policy: RetryPolicy = .default,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.policy = policy
        self.sleep = sleep
    }

    public func intercept(_ request: URLRequest, next: @escaping HTTPHandler) async throws -> HTTPResponse {
        let method = HTTPMethod(rawValue: request.httpMethod ?? "GET")
        guard policy.canRetry(method), policy.maxAttempts > 1 else {
            return try await next(request)
        }

        var attempt = 1
        while true {
            try Task.checkCancellation()
            do {
                let response = try await next(request)
                guard attempt < policy.maxAttempts, policy.shouldRetry(response) else {
                    return response
                }
                try await sleep(policy.delay(afterAttempt: attempt, response: response))
            } catch {
                guard attempt < policy.maxAttempts, policy.shouldRetry(error) else {
                    throw error
                }
                try await sleep(policy.delay(afterAttempt: attempt))
            }
            attempt += 1
        }
    }
}
