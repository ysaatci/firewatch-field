import Foundation

/// Fractal value noise: smooth random fields for fuel load and elevation.
///
/// Each octave places random values on a coarse lattice and interpolates between them;
/// summing octaves of different spacing gives large features with finer detail on top.
enum ValueNoise {
    struct Octave {
        /// Lattice spacing, in cells.
        var spacing: Double
        var weight: Double
    }

    static let landscape = [
        Octave(spacing: 32, weight: 0.6), Octave(spacing: 12, weight: 0.3), Octave(spacing: 4, weight: 0.1),
    ]

    /// A `rows` × `columns` field rescaled to span exactly `0...1`.
    static func field(rows: Int, columns: Int, octaves: [Octave], random: inout SeededRandom) -> Grid<Double> {
        let layers = octaves.map { octave in
            (octave.weight, layer(rows: rows, columns: columns, spacing: octave.spacing, random: &random))
        }
        let summed = Grid(rows: rows, columns: columns) { index in
            layers.reduce(0) { $0 + $1.0 * $1.1[index] }
        }
        let values = summed.values
        guard let low = values.min(), let high = values.max(), high > low else { return summed.map { _ in 0.5 } }
        return summed.map { ($0 - low) / (high - low) }
    }

    private static func layer(rows: Int, columns: Int, spacing: Double, random: inout SeededRandom) -> Grid<Double> {
        let lattice = Grid(rows: Int(Double(rows) / spacing) + 2, columns: Int(Double(columns) / spacing) + 2) { _ in
            random.unit()
        }
        return Grid(rows: rows, columns: columns) { index in
            let y = Double(index.row) / spacing
            let x = Double(index.column) / spacing
            let cell = GridIndex(row: Int(y), column: Int(x))
            let ty = smoothstep(y - y.rounded(.down))
            let tx = smoothstep(x - x.rounded(.down))
            let south = lerp(lattice[cell], lattice[cell.offset(rows: 0, columns: 1)], tx)
            let north = lerp(lattice[cell.offset(rows: 1, columns: 0)], lattice[cell.offset(rows: 1, columns: 1)], tx)
            return lerp(south, north, ty)
        }
    }

    private static func smoothstep(_ t: Double) -> Double { t * t * (3 - 2 * t) }
    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
}
