import FireWatchCore
import Foundation

/// Exponential cooling from a peak temperature towards ambient.
public struct CoolingCurve: Hashable, Sendable {
    public var startMinute: Double
    public var peakCelsius: Double
    /// Minutes for the excess over ambient to fall by a factor of e.
    public var coolingMinutes: Double

    public func celsius(atMinute minute: Double, ambient: Double) -> Double {
        let elapsed = max(minute - startMinute, 0)
        return ambient + (peakCelsius - ambient) * exp(-elapsed / coolingMinutes)
    }
}

/// A spot left smouldering after the fire front passed. Mop-up crews hunt these.
public struct ResidualHotspot: Hashable, Sendable {
    public let id: Hotspot.ID
    public let coordinate: Coordinate
    /// Starts when the cell burns out.
    public let smoulder: CoolingCurve
    /// A later rekindling, if this hotspot has one.
    public let flareUp: CoolingCurve?

    public var appearsAtMinute: Double { smoulder.startMinute }

    /// The surface temperature with nobody intervening, or `nil` before it appears.
    public func celsius(atMinute minute: Double, ambient: Double) -> Double? {
        guard minute >= appearsAtMinute else { return nil }
        let smouldering = smoulder.celsius(atMinute: minute, ambient: ambient)
        guard let flareUp, minute >= flareUp.startMinute else { return smouldering }
        return max(smouldering, flareUp.celsius(atMinute: minute, ambient: ambient))
    }
}

/// Decides where hotspots are left behind and how they cool.
public struct ResidualHotspotModel: Sendable {
    /// Chance a burned-out cell keeps smouldering, multiplied by its fuel (heavy fuel smoulders longer).
    public var smoulderChance = 0.3
    public var peakCelsius: ClosedRange<Double> = 150...650
    public var coolingMinutes: ClosedRange<Double> = 40...180
    public var flareUpChance = 0.25
    /// Minutes after appearing that a flare-up happens.
    public var flareUpDelayMinutes: ClosedRange<Double> = 60...240
    public var flareUpPeakCelsius: ClosedRange<Double> = 200...450
    public var flareUpCoolingMinutes: ClosedRange<Double> = 30...90

    public init() {}

    /// At most one hotspot per burned-out cell, in row-major cell order.
    public func hotspots(from history: FireHistory, on terrain: TerrainGrid, random: inout SeededRandom)
        -> [ResidualHotspot]
    {
        terrain.fuel.indices.compactMap { cell in
            guard let burnedOut = history.burnedOutAt[cell], random.chance(smoulderChance * terrain.fuel[cell])
            else { return nil }
            return makeHotspot(in: cell, at: Double(burnedOut), on: terrain, random: &random)
        }
    }

    private func makeHotspot(in cell: GridIndex, at minute: Double, on terrain: TerrainGrid, random: inout SeededRandom)
        -> ResidualHotspot
    {
        let centre = terrain.planarCentre(of: cell)
        let half = terrain.cellSize / 2
        let position = PlanarPoint(
            x: centre.x + random.uniform(-half...half),
            y: centre.y + random.uniform(-half...half)
        )
        let smoulder = CoolingCurve(
            startMinute: minute,
            peakCelsius: random.uniform(peakCelsius),
            coolingMinutes: random.uniform(coolingMinutes)
        )
        var flareUp: CoolingCurve?
        if random.chance(flareUpChance) {
            flareUp = CoolingCurve(
                startMinute: minute + random.uniform(flareUpDelayMinutes),
                peakCelsius: random.uniform(flareUpPeakCelsius),
                coolingMinutes: random.uniform(flareUpCoolingMinutes)
            )
        }
        return ResidualHotspot(
            id: Hotspot.ID(String(format: "hs-r%03dc%03d", cell.row, cell.column)),
            coordinate: terrain.coordinate(at: position),
            smoulder: smoulder,
            flareUp: flareUp
        )
    }
}
