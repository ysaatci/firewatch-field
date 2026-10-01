import FireWatchAPI
import Testing
import VaporTesting

@testable import FireWatchServer

struct ControlTests {
    func status(_ app: Application) async throws -> ReplayStatusDTO {
        try await app.send(.GET, "v1/control").decoded(as: ReplayStatusDTO.self)
    }

    func control(_ app: Application, _ request: ReplayControlDTO) async throws -> TestingHTTPResponse {
        try await app.send(.POST, "v1/control") { try $0.encode(request) }
    }

    @Test func startsAtConfiguredMinuteAndRunsAtSpeed() async throws {
        try await withTestApp(speed: 60, startMinute: 60) { app, clock in
            #expect(try await status(app).scenarioMinute == 60)
            clock.advance(seconds: 30)
            let status = try await status(app)
            #expect(status.scenarioMinute == 90)
            #expect(status.state == .running)
            #expect(status.preset == "manavgat")
            #expect(status.scenarioMinutes == 240)
        }
    }

    @Test func pauseAndStart() async throws {
        try await withTestApp { app, clock in
            #expect(try await control(app, ReplayControlDTO(action: .pause)).status == .ok)
            clock.advance(seconds: 60)
            #expect(try await status(app).state == .paused)
            #expect(try await status(app).scenarioMinute == 60)
            _ = try await control(app, ReplayControlDTO(action: .start, speed: 120))
            clock.advance(seconds: 30)
            #expect(try await status(app).scenarioMinute == 120)
        }
    }

    @Test func finishesAtTheEnd() async throws {
        try await withTestApp { app, clock in
            clock.advance(seconds: 3_600)
            let state = try await status(app).state
            #expect(state == .finished)
        }
    }

    @Test func resetRestartsWithAnotherPreset() async throws {
        try await withTestApp { app, clock in
            clock.advance(seconds: 60)
            let response = try await control(app, ReplayControlDTO(action: .reset, preset: "stress"))
            let status = try response.decoded(as: ReplayStatusDTO.self)
            #expect(status.preset == "stress")
            #expect(status.scenarioMinute == 60)
            #expect(status.scenarioMinutes == 300)
        }
    }

    @Test(arguments: [
        ReplayControlDTO(action: .start, speed: 0), ReplayControlDTO(action: .start, speed: 601),
        ReplayControlDTO(action: .reset, preset: "nowhere"),
    ])
    func rejectsInvalidRequests(request: ReplayControlDTO) async throws {
        try await withTestApp { app, _ in
            let response = try await control(app, request)
            #expect(response.status == .badRequest)
            #expect(try response.decoded(as: ErrorDTO.self).code == "invalidPayload")
        }
    }

    @Test func rejectsMalformedBodies() async throws {
        try await withTestApp { app, _ in
            let response = try await app.send(.POST, "v1/control") { request in
                request.body = ByteBuffer(string: #"{"action":"rewind"}"#)
            }
            #expect(response.status == .badRequest)
        }
    }

    @Test func unknownRoutesUseTheErrorShape() async throws {
        try await withTestApp { app, _ in
            let response = try await app.send(.GET, "v1/nothing-here")
            #expect(response.status == .notFound)
            #expect(try response.decoded(as: ErrorDTO.self).code == "notFound")
        }
    }
}
