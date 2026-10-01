import FireWatchAPI
import Foundation
import Synchronization
import Testing
import VaporTesting

@testable import FireWatchServer

/// A clock tests move by hand.
final class TestClock: Sendable {
    private let current = Mutex(Date(timeIntervalSince1970: 1_800_000_000))

    var now: Date { current.withLock { $0 } }

    func advance(seconds: Double) {
        current.withLock { $0 = $0.addingTimeInterval(seconds) }
    }
}

let testToken = "test-token"

/// A configured app with a hand-driven clock and no background ticker.
func withTestApp(
    speed: Double = 60,
    startMinute: Double = 60,
    _ test: (Application, TestClock) async throws -> Void
) async throws {
    let clock = TestClock()
    let configuration = ServerConfiguration(
        token: testToken, speed: speed, startMinute: startMinute, tickInterval: nil, now: { clock.now })
    try await withApp(configure: { try await configure($0, configuration: configuration) }) { app in
        try await test(app, clock)
    }
}

extension TestingHTTPResponse {
    /// The body decoded with the API's decoder.
    func decoded<T: Decodable>(as type: T.Type) throws -> T {
        try API.makeDecoder().decode(T.self, from: Data(buffer: body))
    }
}

extension TestingHTTPRequest {
    /// Sets the body to `value` encoded with the API's encoder.
    mutating func encode(_ value: some Encodable) throws {
        body = ByteBuffer(data: try API.makeEncoder().encode(value))
        headers.contentType = .json
    }
}
