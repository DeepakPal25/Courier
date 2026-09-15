# Contributing to Courier

Thanks for your interest in improving Courier.

## Getting started

```bash
git clone https://github.com/YOUR_USERNAME/Courier.git
cd Courier
swift test
```

You need Xcode 16 or later (Swift 6).

## Guidelines

- **Open an issue first** for anything larger than a bug fix, so we can agree on the design before you write code.
- **Keep the library dependency-free** and compiling cleanly under Swift 6 strict concurrency. Avoid `@unchecked Sendable` in library code.
- **Add tests** for new behaviour using Swift Testing and `MockTransport`. Inject clocks and sinks rather than sleeping in tests.
- **Document public API** with DocC comments.
- **Update CHANGELOG.md** under *Unreleased*.

## Pull requests

1. Fork the repository and create a branch from `main`.
2. Make your change with tests.
3. Make sure `swift test` passes.
4. Open a pull request describing what changed and why.

By contributing, you agree that your contributions will be licensed under the MIT License.
