import FireWatchCore
import Foundation

/// Everything that defines a scenario. The same configuration always produces the same scenario.
public struct ScenarioConfiguration: Sendable {
    public var seed: UInt64
    public var centre: Coordinate
    public var rows: Int
    public var columns: Int
    /// Cell width, in metres.
    public var cellSize: Double
    public var minutes: Int
    /// Where the fire starts, in metres east (`x`) and north (`y`) of the centre.
    public var ignition: PlanarPoint
    public var ambientCelsius: Double
    public var perimeterIntervalMinutes: Int
    public var fire: FireSpreadModel
    public var residuals: ResidualHotspotModel
    public var survey: DroneSurvey

    public init(
        seed: UInt64,
        centre: Coordinate,
        rows: Int = 120,
        columns: Int = 120,
        cellSize: Double = 50,
        minutes: Int = 240,
        ignition: PlanarPoint = PlanarPoint(x: -1_500, y: -500),
        wind: Wind = Wind(speed: 6, fromDegrees: 250),
        ambientCelsius: Double = 30,
        perimeterIntervalMinutes: Int = 5
    ) {
        self.seed = seed
        self.centre = centre
        self.rows = rows
        self.columns = columns
        self.cellSize = cellSize
        self.minutes = minutes
        self.ignition = ignition
        self.ambientCelsius = ambientCelsius
        self.perimeterIntervalMinutes = perimeterIntervalMinutes
        self.fire = FireSpreadModel(wind: wind)
        self.residuals = ResidualHotspotModel()
        self.survey = DroneSurvey()
    }
}

/// A precomputed wildfire: how it spread, what it left smouldering, and when drones saw it.
/// Times are minutes from the start of the scenario.
public struct Scenario: Sendable {
    public let configuration: ScenarioConfiguration
    public let terrain: TerrainGrid
    public let fire: FireHistory
    public let hotspots: [ResidualHotspot]
    public let routes: [SurveyRoute]
    /// Every drone measurement of a hotspot, in time order.
    public let passes: [DronePass]
    /// The fire outline every ``ScenarioConfiguration/perimeterIntervalMinutes``.
    public let perimeters: [ScenarioPerimeter]

    public init(_ configuration: ScenarioConfiguration) {
        self.configuration = configuration
        // Each part draws from its own stream, so tuning one never reshuffles the others.
        let root = SeededRandom(seed: configuration.seed)
        var terrainRandom = root.fork(1)
        var fireRandom = root.fork(2)
        var residualRandom = root.fork(3)

        terrain = TerrainGrid.generate(
            rows: configuration.rows,
            columns: configuration.columns,
            cellSize: configuration.cellSize,
            centre: configuration.centre,
            random: &terrainRandom
        )
        let ignition = Self.ignitionCell(near: configuration.ignition, on: terrain)
        fire = configuration.fire.run(
            on: terrain, ignitions: ignition.map { [$0] } ?? [], minutes: configuration.minutes, random: &fireRandom)
        hotspots = configuration.residuals.hotspots(from: fire, on: terrain, random: &residualRandom)
        routes = configuration.survey.routes(over: terrain)
        passes = configuration.survey.passes(
            of: hotspots,
            routes: routes,
            terrain: terrain,
            minutes: configuration.minutes,
            ambientCelsius: configuration.ambientCelsius
        )
        var perimeters: [ScenarioPerimeter] = []
        for minute in stride(from: 0, through: configuration.minutes, by: configuration.perimeterIntervalMinutes) {
            let polygons = terrain.polygons(of: fire.affectedMask(atMinute: minute))
            perimeters.append(ScenarioPerimeter(minute: minute, polygons: polygons))
        }
        self.perimeters = perimeters
    }

    /// The most heavily fuelled cell within three cells of `point`, so the fire never starts on bare rock.
    private static func ignitionCell(near point: PlanarPoint, on terrain: TerrainGrid) -> GridIndex? {
        guard let target = terrain.cell(containing: point) else { return nil }
        let candidates = (-3...3).flatMap { rows in (-3...3).map { target.offset(rows: rows, columns: $0) } }
        return
            candidates
            .filter { (terrain.fuel.value(at: $0) ?? 0) > 0 }
            .max { (terrain.fuel[$0], $1) < (terrain.fuel[$1], $0) }
    }
}

/// The fire outline at one minute of a scenario.
public struct ScenarioPerimeter: Hashable, Sendable {
    public var minute: Int
    public var polygons: [Polygon]

    public var areaSquareMetres: Double {
        polygons.reduce(0) { $0 + $1.areaSquareMetres }
    }
}
