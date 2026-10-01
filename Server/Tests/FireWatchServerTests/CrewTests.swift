import FireWatchAPI
import FireWatchCore
import Foundation
import Testing
import VaporTesting

@testable import FireWatchServer

struct CrewTests {
    func send(_ app: Application, _ command: CommandDTO) async throws -> TestingHTTPResponse {
        try await app.testing().sendRequest(.POST, "v1/commands") { try $0.encode(command) }
    }

    /// A hotspot the simulation has already detected, hottest first so it is still being observed.
    func detectedHotspot(_ app: Application) async throws -> Hotspot {
        let state = try await #require(app.simulator).simulation.state
        return try #require(state.hotspots.values.max { $0.temperatureCelsius < $1.temperatureCelsius })
    }

    func command(_ action: String, on hotspot: Hotspot, id: String = UUID().uuidString) -> CommandDTO {
        CommandDTO(id: id, hotspotID: hotspot.id.rawValue, action: action, issuedAt: .distantPast)
    }

    @Test func appliesCommandsAndStampsScenarioTime() async throws {
        try await withTestApp { app, _ in
            let hotspot = try await detectedHotspot(app)
            let response = try await send(app, command("assign", on: hotspot, id: "c-1"))
            #expect(response.status == .ok)
            #expect(try response.decoded(as: ReceiptDTO.self) == ReceiptDTO(id: "c-1", outcome: .applied))
            let simulation = try #require(app.simulator).simulation
            #expect(await simulation.state.hotspots[hotspot.id]?.status == .assigned)
        }
    }

    @Test func retriesAreDuplicatesNotReapplied() async throws {
        try await withTestApp { app, _ in
            let hotspot = try await detectedHotspot(app)
            let extinguish = command("extinguish", on: hotspot, id: "c-1")
            _ = try await send(app, extinguish)
            let retry = try await send(app, extinguish)
            #expect(try retry.decoded(as: ReceiptDTO.self).outcome == .duplicate)
            let simulation = try #require(app.simulator).simulation
            #expect(await simulation.state.hotspots[hotspot.id]?.status == .extinguished)
        }
    }

    @Test func illegalActionsConflict() async throws {
        try await withTestApp { app, _ in
            let hotspot = try await detectedHotspot(app)
            let response = try await send(app, command("verifyCold", on: hotspot))
            #expect(response.status == .conflict)
            let error = try response.decoded(as: ErrorDTO.self)
            #expect(error == ErrorDTO(code: "notAllowed", message: "verifyCold is not allowed from new"))
        }
    }

    @Test func unknownHotspotsAreNotFound() async throws {
        try await withTestApp { app, _ in
            let response = try await send(
                app, CommandDTO(id: "c", hotspotID: "hs-nowhere", action: "assign", issuedAt: .now))
            #expect(response.status == .notFound)
            #expect(try response.decoded(as: ErrorDTO.self).code == "unknownHotspot")
        }
    }

    @Test func unknownActionsAreInvalid() async throws {
        try await withTestApp { app, _ in
            let hotspot = try await detectedHotspot(app)
            let response = try await send(app, command("douse", on: hotspot))
            #expect(response.status == .badRequest)
            #expect(try response.decoded(as: ErrorDTO.self).code == "invalidPayload")
        }
    }

    @Test func extinguishedHotspotsReadCoolUnlessTheyFlareUp() async throws {
        try await withTestApp { app, clock in
            let simulation = try #require(app.simulator).simulation
            let hotspot = try await detectedHotspot(app)
            _ = try await send(app, command("extinguish", on: hotspot))
            for _ in 0..<60 {  // an hour of scenario time, a minute per tick
                clock.advance(seconds: 1)
                _ = await simulation.advance()
            }
            let later = try #require(await simulation.state.hotspots[hotspot.id])
            #expect(later.readings.count > hotspot.readings.count)  // drones came back
            #expect(later.status == .flaredUp || later.temperatureCelsius < 40)
        }
    }

    @Test func reportsAreStoredOnceAndAcceptPhotos() async throws {
        try await withTestApp { app, _ in
            let report = ReportDTO(
                id: "r-1", createdAt: .now, location: Position(longitude: 31.47, latitude: 36.83),
                severity: "high", note: "Smoke behind the ridge", photoJPEG: Data(count: 2_000_000))
            let first = try await app.testing().sendRequest(.POST, "v1/reports") { try $0.encode(report) }
            let retry = try await app.testing().sendRequest(.POST, "v1/reports") { try $0.encode(report) }
            #expect(try first.decoded(as: ReceiptDTO.self).outcome == .applied)
            #expect(try retry.decoded(as: ReceiptDTO.self).outcome == .duplicate)
            let simulation = try #require(app.simulator).simulation
            #expect(await simulation.reports.count == 1)
        }
    }

    @Test func reportsWithUnknownSeverityAreInvalid() async throws {
        try await withTestApp { app, _ in
            let report = ReportDTO(
                id: "r-1", createdAt: .now, location: Position(longitude: 0, latitude: 0), severity: "huge",
                note: "", photoJPEG: nil)
            let response = try await app.testing().sendRequest(.POST, "v1/reports") { try $0.encode(report) }
            #expect(response.status == .badRequest)
        }
    }

    @Test func resetForgetsCommandsAndReports() async throws {
        try await withTestApp { app, _ in
            let hotspot = try await detectedHotspot(app)
            _ = try await send(app, command("assign", on: hotspot, id: "c-1"))
            _ = try await app.testing().sendRequest(.POST, "v1/control") {
                try $0.encode(ReplayControlDTO(action: .reset))
            }
            let again = try await send(app, command("assign", on: hotspot, id: "c-1"))
            #expect(try again.decoded(as: ReceiptDTO.self).outcome == .applied)
        }
    }
}
