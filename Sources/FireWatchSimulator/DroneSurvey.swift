import FireWatchCore
import Foundation

/// One drone's lawnmower route over its strip of the area, flown back and forth.
public struct SurveyRoute: Sendable {
    public let droneID: Drone.ID
    public let name: String
    /// Waypoints in metres from the grid centre.
    let waypoints: [PlanarPoint]
    /// Distance along the route to each waypoint.
    private let distances: [Double]
    let speed: Double
    let altitudeMetres: Double
    /// Minutes per battery; the battery is swapped instantly when it runs low.
    let enduranceMinutes: Double

    init(
        droneID: Drone.ID,
        name: String,
        waypoints: [PlanarPoint],
        speed: Double,
        altitudeMetres: Double,
        enduranceMinutes: Double
    ) {
        precondition(waypoints.count >= 2, "a route needs at least two waypoints")
        self.droneID = droneID
        self.name = name
        self.waypoints = waypoints
        self.speed = speed
        self.altitudeMetres = altitudeMetres
        self.enduranceMinutes = enduranceMinutes
        var total = 0.0
        distances =
            [0]
            + zip(waypoints, waypoints.dropFirst()).map { a, b in
                total += hypot(b.x - a.x, b.y - a.y)
                return total
            }
    }

    var length: Double { distances[distances.count - 1] }

    /// Where the drone is `seconds` into the scenario, and which way it is heading.
    func location(atSecond seconds: Double) -> (point: PlanarPoint, headingDegrees: Double) {
        // Fly to the end, then back along the same route.
        let travelled = (seconds * speed).truncatingRemainder(dividingBy: 2 * length)
        let returning = travelled > length
        let distance = returning ? 2 * length - travelled : travelled
        let segment = min(distances.lastIndex { $0 <= distance } ?? 0, waypoints.count - 2)
        let from = waypoints[segment]
        let to = waypoints[segment + 1]
        let t = (distance - distances[segment]) / max(distances[segment + 1] - distances[segment], .ulpOfOne)
        let point = PlanarPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
        let direction: Double = returning ? -1 : 1
        let degrees = atan2((to.x - from.x) * direction, (to.y - from.y) * direction) * 180 / .pi
        return (point, degrees < 0 ? degrees + 360 : degrees)
    }

    /// Remaining battery `seconds` into the scenario.
    func battery(atSecond seconds: Double) -> Double {
        let cycle = (seconds / 60 / enduranceMinutes).truncatingRemainder(dividingBy: 1)
        return 1 - 0.8 * cycle
    }
}

/// Plans the fleet's routes and works out when drones see each hotspot.
public struct DroneSurvey: Sendable {
    public var names = ["Kartal", "Şahin", "Doğan", "Atmaca"]
    public var droneCount = 3
    /// Metres per second.
    public var speed = 15.0
    /// Radius of the thermal camera's ground footprint, in metres.
    public var footprintRadius = 250.0
    public var altitudeMetres = 120.0
    public var enduranceMinutes = 40.0
    /// A hotspot is first detected only at or above this temperature.
    public var detectionCelsius = 60.0
    /// Minimum minutes between two measurements of the same hotspot.
    public var revisitMinutes = 3.0
    /// Seconds between sampled drone positions.
    public var sampleSeconds = 20.0

    public init() {}

    /// One route per drone, each covering an equal vertical strip of the terrain.
    public func routes(over terrain: TerrainGrid) -> [SurveyRoute] {
        let width = Double(terrain.columns) * terrain.cellSize
        let height = Double(terrain.rows) * terrain.cellSize
        let laneSpacing = footprintRadius * 1.6  // overlapping footprints leave no gaps
        let south = -height / 2 + footprintRadius / 2
        let north = height / 2 - footprintRadius / 2
        let stripWidth = width / Double(droneCount)
        return (0..<droneCount).map { index in
            let west = -width / 2 + Double(index) * stripWidth
            let lanes = max(Int((stripWidth / laneSpacing).rounded(.up)), 1)
            let waypoints = (0..<lanes).flatMap { lane -> [PlanarPoint] in
                let x = west + (Double(lane) + 0.5) * stripWidth / Double(lanes)
                let ends = [PlanarPoint(x: x, y: south), PlanarPoint(x: x, y: north)]
                return lane.isMultiple(of: 2) ? ends : ends.reversed()
            }
            return SurveyRoute(
                droneID: Drone.ID("drone-\(index + 1)"),
                name: "\(names[index % names.count])-\(index + 1)",
                waypoints: waypoints,
                speed: speed,
                altitudeMetres: altitudeMetres,
                enduranceMinutes: enduranceMinutes
            )
        }
    }

    /// The sample times, in seconds, covering `minutes`.
    public func sampleTimes(minutes: Int) -> [Double] {
        Array(stride(from: 0, through: Double(minutes) * 60, by: sampleSeconds))
    }

    /// Every time a drone measures a hotspot, in time order.
    ///
    /// Detection uses each hotspot's undisturbed temperature: crews can only act on
    /// hotspots that have already been detected, so their interventions never change
    /// whether a detection happens.
    public func passes(
        of hotspots: [ResidualHotspot],
        routes: [SurveyRoute],
        terrain: TerrainGrid,
        minutes: Int,
        ambientCelsius: Double
    ) -> [DronePass] {
        let positions = hotspots.map { terrain.projection.project($0.coordinate) }
        let buckets = SpatialBuckets(points: positions, size: footprintRadius)
        var lastSeenMinute = [Double?](repeating: nil, count: hotspots.count)
        var passes: [DronePass] = []
        for second in sampleTimes(minutes: minutes) {
            let minute = second / 60
            for route in routes {
                let drone = route.location(atSecond: second).point
                for index in buckets.indices(near: drone) {
                    let distance = hypot(positions[index].x - drone.x, positions[index].y - drone.y)
                    guard distance <= footprintRadius,
                        let celsius = hotspots[index].celsius(atMinute: minute, ambient: ambientCelsius)
                    else { continue }
                    if let last = lastSeenMinute[index] {
                        guard minute - last >= revisitMinutes else { continue }
                    } else {
                        guard celsius >= detectionCelsius else { continue }
                    }
                    lastSeenMinute[index] = minute
                    passes.append(
                        DronePass(minute: minute, hotspot: index, droneID: route.droneID, distance: distance))
                }
            }
        }
        return passes
    }
}

/// A drone measuring a hotspot.
public struct DronePass: Hashable, Sendable {
    public var minute: Double
    /// Index into the scenario's hotspot list.
    public var hotspot: Int
    public var droneID: Drone.ID
    /// Metres from the point under the drone; readings get less certain towards the footprint edge.
    public var distance: Double
}

/// Points grouped into square buckets for fast "what's near here" queries.
struct SpatialBuckets {
    private struct Key: Hashable {
        var x: Int
        var y: Int
    }

    private let size: Double
    private var buckets: [Key: [Int]] = [:]

    init(points: [PlanarPoint], size: Double) {
        self.size = size
        for (index, point) in points.enumerated() {
            buckets[key(for: point), default: []].append(index)
        }
    }

    private func key(for point: PlanarPoint) -> Key {
        Key(x: Int((point.x / size).rounded(.down)), y: Int((point.y / size).rounded(.down)))
    }

    /// Indices of points within one bucket of `point`, in ascending order.
    func indices(near point: PlanarPoint) -> [Int] {
        let centre = key(for: point)
        return (-1...1).flatMap { dx in
            (-1...1).flatMap { dy in buckets[Key(x: centre.x + dx, y: centre.y + dy)] ?? [] }
        }
        .sorted()
    }
}
