import FireWatchAPI
import FireWatchCore
import Vapor

/// Read endpoints: the state as of the last tick, so it always matches what the stream has sent (FR-S1).
struct FeedController: RouteCollection {
    let simulation: FireSimulation

    func boot(routes: any RoutesBuilder) throws {
        routes.get("snapshot") { _ in
            let (state, time) = await simulation.current()
            return try Response.json(SnapshotDTO(state, generatedAt: time))
        }
        routes.get("hotspots") { request in
            let box = try Self.boundingBox(from: request.query["bbox"])
            let hotspots = await simulation.current().state.hotspots.values
                .filter { box?.contains($0.coordinate) ?? true }
                .sorted { $0.id < $1.id }
            return try Response.json(hotspots.map(HotspotDTO.init))
        }
        routes.get("perimeters") { _ in
            let perimeters = await simulation.current().state.perimeters
            return try Response.json(PerimeterHistoryDTO(features: perimeters.map(PerimeterDTO.init)))
        }
        routes.get("drones") { _ in
            let drones = await simulation.current().state.drones.values.sorted { $0.id < $1.id }
            return try Response.json(drones.map(DroneDTO.init))
        }
    }

    /// Parses `minLon,minLat,maxLon,maxLat`; `nil` when the parameter is absent.
    static func boundingBox(from text: String?) throws(APIFailure) -> BoundingBox? {
        guard let text else { return nil }
        let numbers = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard numbers.count == 4, numbers[0] <= numbers[2], numbers[1] <= numbers[3] else {
            throw .invalidPayload("bbox must be minLon,minLat,maxLon,maxLat")
        }
        return BoundingBox(
            southWest: Coordinate(latitude: numbers[1], longitude: numbers[0]),
            northEast: Coordinate(latitude: numbers[3], longitude: numbers[2])
        )
    }
}
