import FireWatchAPI
import Testing
import VaporTesting

@testable import FireWatchServer

struct FaultTests {
    func setFaults(_ app: Application, _ faults: FaultsDTO) async throws -> TestingHTTPResponse {
        try await app.send(.POST, "v1/control/faults") { try $0.encode(faults) }
    }

    @Test func droppedRequestsFailWith503() async throws {
        try await withTestApp { app, _ in
            #expect(try await setFaults(app, FaultsDTO(latencyMilliseconds: 0, dropRate: 1)).status == .ok)
            let dropped = try await app.send(.GET, "v1/snapshot")
            #expect(dropped.status == .serviceUnavailable)
            #expect(try dropped.decoded(as: ErrorDTO.self).code == "injectedFault")

            _ = try await setFaults(app, .none)
            #expect(try await app.send(.GET, "v1/snapshot").status == .ok)
        }
    }

    @Test func controlStaysReachableWhileDropping() async throws {
        try await withTestApp { app, _ in
            _ = try await setFaults(app, FaultsDTO(latencyMilliseconds: 0, dropRate: 1))
            #expect(try await app.send(.GET, "v1/control").status == .ok)
            let current = try await app.send(.GET, "v1/control/faults")
            #expect(try current.decoded(as: FaultsDTO.self).dropRate == 1)
        }
    }

    @Test func latencyDelaysRequests() async throws {
        try await withTestApp { app, _ in
            _ = try await setFaults(app, FaultsDTO(latencyMilliseconds: 200, dropRate: 0))
            let started = ContinuousClock.now
            _ = try await app.send(.GET, "health")  // outside /v1: not delayed
            let afterHealth = ContinuousClock.now
            _ = try await app.send(.GET, "v1/drones")
            #expect(afterHealth - started < .milliseconds(200))
            #expect(ContinuousClock.now - afterHealth >= .milliseconds(200))
        }
    }

    @Test(arguments: [
        FaultsDTO(latencyMilliseconds: -1, dropRate: 0), FaultsDTO(latencyMilliseconds: 30_001, dropRate: 0),
        FaultsDTO(latencyMilliseconds: 0, dropRate: 1.5),
    ])
    func rejectsOutOfRangeSettings(faults: FaultsDTO) async throws {
        try await withTestApp { app, _ in
            let status = try await setFaults(app, faults).status
            #expect(status == .badRequest)
        }
    }
}
