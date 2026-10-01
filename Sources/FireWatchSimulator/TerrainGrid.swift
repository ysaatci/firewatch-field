import FireWatchCore

/// The landscape the fire burns across: square cells with a fuel load and an elevation.
public struct TerrainGrid: Sendable {
    /// Cell width, in metres.
    public let cellSize: Double
    /// Projection centred on the middle of the grid.
    public let projection: LocalProjection
    /// Burnable material in `0...1`; 0 means bare rock, roads or fields that don't burn.
    public let fuel: Grid<Double>
    /// Ground height in metres.
    public let elevation: Grid<Double>

    public var rows: Int { fuel.rows }
    public var columns: Int { fuel.columns }

    public init(cellSize: Double, centre: Coordinate, fuel: Grid<Double>, elevation: Grid<Double>) {
        precondition(fuel.rows == elevation.rows && fuel.columns == elevation.columns, "layers must match")
        self.cellSize = cellSize
        self.projection = LocalProjection(origin: centre)
        self.fuel = fuel
        self.elevation = elevation
    }

    /// Random hilly terrain with patches of unburnable ground.
    public static func generate(
        rows: Int,
        columns: Int,
        cellSize: Double,
        centre: Coordinate,
        maxElevation: Double = 400,
        bareGroundFraction: Double = 0.2,
        random: inout SeededRandom
    ) -> TerrainGrid {
        let vegetation = ValueNoise.field(rows: rows, columns: columns, octaves: ValueNoise.landscape, random: &random)
        let height = ValueNoise.field(rows: rows, columns: columns, octaves: ValueNoise.landscape, random: &random)
        let fuel = vegetation.map { value in
            value < bareGroundFraction ? 0 : 0.3 + 0.7 * (value - bareGroundFraction) / (1 - bareGroundFraction)
        }
        return TerrainGrid(cellSize: cellSize, centre: centre, fuel: fuel, elevation: height.map { $0 * maxElevation })
    }

    /// The centre of `index` in metres from the grid centre.
    public func planarCentre(of index: GridIndex) -> PlanarPoint {
        PlanarPoint(
            x: (Double(index.column) + 0.5 - Double(columns) / 2) * cellSize,
            y: (Double(index.row) + 0.5 - Double(rows) / 2) * cellSize
        )
    }

    public func centre(of index: GridIndex) -> Coordinate {
        coordinate(at: planarCentre(of: index))
    }

    /// The cell containing `point` (metres from the grid centre), or `nil` outside the grid.
    public func cell(containing point: PlanarPoint) -> GridIndex? {
        let index = GridIndex(
            row: Int((point.y / cellSize + Double(rows) / 2).rounded(.down)),
            column: Int((point.x / cellSize + Double(columns) / 2).rounded(.down))
        )
        return fuel.contains(index) ? index : nil
    }

    public func cell(containing coordinate: Coordinate) -> GridIndex? {
        cell(containing: projection.project(coordinate))
    }
}
