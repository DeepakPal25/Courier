import Foundation

public protocol ResponseDecoder: Sendable {
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T
}

// JSONDecoder isn't guaranteed Sendable on all supported SDK versions, so we
// create a new one per call rather than sharing an instance. It's cheap enough
// that it doesn't matter next to a network round trip.
public struct JSONResponseDecoder: ResponseDecoder {
    private let configure: @Sendable (JSONDecoder) -> Void

    public init(configure: @escaping @Sendable (JSONDecoder) -> Void = { _ in }) {
        self.configure = configure
    }

    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        configure(decoder)
        return try decoder.decode(type, from: data)
    }
}
