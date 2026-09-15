# ``Courier``

A small, composable HTTP client built for Swift 6 strict concurrency.

## Overview

Create an ``HTTPClient`` with a base URL and a stack of ``Middleware``, then send typed ``Request`` values:

```swift
let client = HTTPClient(
    baseURL: URL(string: "https://api.example.com/v1")!,
    middleware: [RetryMiddleware(), AuthMiddleware(tokens: tokens)]
)

let user = try await client.send(Request<User>.get("users/42"))
```

Middleware runs in array order on the way out and in reverse on the way back.

## Topics

### Essentials

- ``HTTPClient``
- ``Request``
- ``HTTPResponse``
- ``CourierError``
- ``EmptyResponse``

### Middleware

- ``Middleware``
- ``HTTPHandler``
- ``ClosureMiddleware``
- ``RetryMiddleware``
- ``RetryPolicy``
- ``Backoff``
- ``AuthMiddleware``
- ``TokenRefresher``
- ``DeduplicationMiddleware``
- ``LoggingMiddleware``

### Customization

- ``HTTPTransport``
- ``URLSessionTransport``
- ``ResponseDecoder``
- ``JSONResponseDecoder``
- ``HTTPMethod``
