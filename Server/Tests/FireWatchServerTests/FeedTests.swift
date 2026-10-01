import FireWatchAPI
import FireWatchCore
import Testing
import VaporTesting

@testable import FireWatchServer

struct FeedTests {
    func get<T: Decodable>(_ app: Application, _ path: String, as type: T.Type) async throws -> T {
        let response = try await app.send(.GET, path)
        #expect(response.status == .ok)
        return try response.decoded(as: T.self)
    }

    @Test func snapshotMatchesTheSimulation() async throws {
        try await withTestApp { app, clock in
            let simulation = try #require(app.simulator).simulation
            clock.advance(seconds: 30)
            _ = await simulation.advance()

            let snapshot = try await get(app, "v1/snapshot", as: SnapshotDTO.self)
            let (state, time) = await simulation.current()
            #expect(snapshot.generatedAt == time)
            #expect(try snapshot.fireState().hotspots == state.hotspots)
            #expect(snapshot.drones.count == 3)
            #expect(snapshot.perimeter != nil)
        }
    }

    @Test func snapshotOnlyMovesWhenTheSimulationTicks() async throws {
        try await withTestApp { app, clock in
            let before = try await get(app, "v1/snapshot", as: SnapshotDTO.self)
            clock.advance(seconds: 60)
            let unticked = try await get(app, "v1/snapshot", as: SnapshotDTO.self)
            #expect(unticked == before)
        }
    }

    @Test func hotspotsFilterByBoundingBox() async throws {
        try await withTestApp { app, _ in
            let all = try await get(app, "v1/hotspots", as: [HotspotDTO].self)
            let target = try #require(all.first)
            let (lon, lat) = (target.location.longitude, target.location.latitude)
            let box = "\(lon - 0.00001),\(lat - 0.00001),\(lon + 0.00001),\(lat + 0.00001)"
            let filtered = try await get(app, "v1/hotspots?bbox=\(box)", as: [HotspotDTO].self)
            #expect(all.count > 1)
            #expect(filtered.map(\.id) == [target.id])
        }
    }

    @Test(arguments: ["1,2,3", "a,b,c,d", "5,5,1,1"])
    func rejectsMalformedBoundingBoxes(bbox: String) async throws {
        try await withTestApp { app, _ in
            let response = try await app.send(.GET, "v1/hotspots?bbox=\(bbox)")
            #expect(response.status == .badRequest)
        }
    }

    @Test func perimeterHistoryIsAFeatureCollection() async throws {
        try await withTestApp { app, _ in
            let history = try await get(app, "v1/perimeters", as: PerimeterHistoryDTO.self)
            let times = history.features.map(\.properties.time)
            #expect(history.features.count == 12)  // minutes 0, 5, …, 55: the start minute itself is next tick
            #expect(times == times.sorted())
        }
    }

    @Test func dronesAreListedInIDOrder() async throws {
        try await withTestApp { app, _ in
            let drones = try await get(app, "v1/drones", as: [DroneDTO].self)
            #expect(drones.map(\.id) == ["drone-1", "drone-2", "drone-3"])
            #expect(drones.allSatisfy { !$0.track.isEmpty })
        }
    }
}
