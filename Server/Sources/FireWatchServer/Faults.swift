import FireWatchAPI
import Vapor

/// The current fault settings, and the dice deciding which requests fail (FR-S5).
actor FaultInjector {
    static let latencyRange = 0...30_000

    private(set) var settings = FaultsDTO.none
    /// A uniform value in `0..<1`; injectable so tests can force outcomes.
    private let roll: @Sendable () -> Double

    init(roll: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }) {
        self.roll = roll
    }

    /// - Throws: ``APIFailure`` for latency or drop rate out of range.
    func update(_ settings: FaultsDTO) throws(APIFailure) -> FaultsDTO {
        guard Self.latencyRange.contains(settings.latencyMilliseconds) else {
            throw .invalidPayload("latencyMilliseconds must be within \(Self.latencyRange)")
        }
        guard (0...1).contains(settings.dropRate) else { throw .invalidPayload("dropRate must be within 0...1") }
        self.settings = settings
        return settings
    }

    func shouldDrop() -> Bool {
        settings.dropRate > 0 && roll() < settings.dropRate
    }
}

/// Slows down or fails `/v1` requests as configured. Control routes are exempt, so faults
/// can always be switched off again.
struct FaultMiddleware: AsyncMiddleware {
    let faults: FaultInjector

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard !request.url.path.hasPrefix("/\(API.pathPrefix)/control") else {
            return try await next.respond(to: request)
        }
        let latency = await faults.settings.latencyMilliseconds
        if latency > 0 { try await Task.sleep(for: .milliseconds(latency)) }
        if await faults.shouldDrop() {
            throw APIFailure(status: .serviceUnavailable, code: "injectedFault", message: "Dropped by fault injection")
        }
        return try await next.respond(to: request)
    }
}
