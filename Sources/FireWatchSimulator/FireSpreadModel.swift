import FireWatchCore
import Foundation

/// Wind at the fire, which pushes spread downwind.
public struct Wind: Hashable, Sendable {
    /// Metres per second.
    public var speed: Double
    /// Direction the wind blows *from*, in degrees clockwise from north (meteorological convention).
    public var fromDegrees: Double

    public init(speed: Double, fromDegrees: Double) {
        self.speed = speed
        self.fromDegrees = fromDegrees
    }

    public static let calm = Wind(speed: 0, fromDegrees: 0)

    /// Unit vector (east, north) pointing the way the wind blows.
    var downwind: PlanarPoint {
        let toward = (fromDegrees + 180) * .pi / 180
        return PlanarPoint(x: sin(toward), y: cos(toward))
    }
}

/// A cellular-automaton fire model (D5): believable, cheap, and easy to explain.
///
/// Every minute, each burning cell may ignite each unburned neighbour (8-connected) with
/// probability `ignitionRate × fuel × wind factor × slope factor`, divided by the distance
/// in cells so diagonals spread proportionally slower. A cell burns for a time that grows
/// with its fuel, then burns out.
public struct FireSpreadModel: Sendable {
    /// Per-minute ignition chance between adjacent, fully fuelled, flat cells in calm air.
    public var ignitionRate = 0.12
    public var wind: Wind
    /// Strength of the wind bias, per m/s. Downwind spread is multiplied by `exp(effect × speed)`.
    public var windEffect = 0.15
    /// Strength of the slope bias, per unit of rise over run. Fire runs uphill.
    public var slopeEffect = 3.0
    /// Minutes a cell burns, from lightest to heaviest fuel.
    public var burnMinutes: ClosedRange<Double> = 8...20

    public init(wind: Wind) {
        self.wind = wind
    }

    private static let neighbourOffsets = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]

    /// Burns `terrain` for `minutes`, starting from `ignitions` at minute 0.
    public func run(
        on terrain: TerrainGrid,
        ignitions: [GridIndex],
        minutes: Int,
        random: inout SeededRandom
    ) -> FireHistory {
        var history = FireHistory(rows: terrain.rows, columns: terrain.columns)
        var burning = ignitions.filter { (terrain.fuel.value(at: $0) ?? 0) > 0 }.sorted()
        for cell in burning { history.ignitedAt[cell] = 0 }

        for minute in 1...max(minutes, 1) {
            var ignitedNow: [GridIndex] = []
            for cell in burning {
                for (rows, columns) in Self.neighbourOffsets {
                    let neighbour = cell.offset(rows: rows, columns: columns)
                    guard (terrain.fuel.value(at: neighbour) ?? 0) > 0, history.ignitedAt[neighbour] == nil else {
                        continue
                    }
                    if random.chance(ignitionProbability(from: cell, to: neighbour, on: terrain)) {
                        history.ignitedAt[neighbour] = minute
                        ignitedNow.append(neighbour)
                    }
                }
            }
            burning.removeAll { cell in
                guard let ignited = history.ignitedAt[cell], minute >= ignited + burnDuration(of: cell, on: terrain)
                else { return false }
                history.burnedOutAt[cell] = minute
                return true
            }
            burning = (burning + ignitedNow).sorted()
        }
        return history
    }

    func ignitionProbability(from source: GridIndex, to target: GridIndex, on terrain: TerrainGrid) -> Double {
        let east = Double(target.column - source.column)
        let north = Double(target.row - source.row)
        let cells = hypot(east, north)
        let alignment = (east * wind.downwind.x + north * wind.downwind.y) / cells
        let windFactor = exp(windEffect * wind.speed * alignment)
        let rise = (terrain.elevation[target] - terrain.elevation[source]) / (cells * terrain.cellSize)
        let slopeFactor = exp(slopeEffect * rise)
        return min(1, ignitionRate * terrain.fuel[target] * windFactor * slopeFactor / cells)
    }

    func burnDuration(of cell: GridIndex, on terrain: TerrainGrid) -> Int {
        let span = burnMinutes.upperBound - burnMinutes.lowerBound
        return Int((burnMinutes.lowerBound + span * terrain.fuel[cell]).rounded())
    }
}

/// When each cell caught fire and burned out, in minutes from the start. `nil` means never.
public struct FireHistory: Hashable, Sendable {
    public internal(set) var ignitedAt: Grid<Int?>
    public internal(set) var burnedOutAt: Grid<Int?>

    init(rows: Int, columns: Int) {
        ignitedAt = Grid(rows: rows, columns: columns, repeating: nil)
        burnedOutAt = Grid(rows: rows, columns: columns, repeating: nil)
    }

    /// Whether `cell` had caught fire by `minute` (burning or burned out).
    public func hasIgnited(_ cell: GridIndex, by minute: Int) -> Bool {
        ignitedAt[cell].map { $0 <= minute } ?? false
    }

    /// Cells that had caught fire by `minute`.
    public func affectedMask(atMinute minute: Int) -> Grid<Bool> {
        ignitedAt.map { $0.map { $0 <= minute } ?? false }
    }
}
