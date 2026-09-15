# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0] - 2026-10-02

### Added
- `HTTPClient` with typed `Request<Response>` values and a middleware pipeline.
- `RetryMiddleware` with exponential backoff, full jitter and `Retry-After` support.
- `AuthMiddleware` and `TokenRefresher`, which coalesces concurrent token refreshes.
- `DeduplicationMiddleware` for sharing identical in-flight `GET`/`HEAD` requests.
- `LoggingMiddleware` with sensitive-header redaction.
- `CourierTesting` module with `MockTransport`.
- DocC documentation and GitHub Actions CI.
