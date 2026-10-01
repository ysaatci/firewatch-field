/// Which hotspots the list shows (FR-4).
public struct HotspotFilter: Hashable, Sendable {
    public var statuses: Set<HotspotStatus>
    public var minimumSeverity: Severity

    /// Everything still needing work, at any severity: verified-cold hotspots are hidden.
    public static let open = HotspotFilter(
        statuses: [.new, .assigned, .extinguished, .flaredUp], minimumSeverity: .low)
    public static let everything = HotspotFilter(statuses: Set(HotspotStatus.allCases), minimumSeverity: .low)

    public init(statuses: Set<HotspotStatus>, minimumSeverity: Severity) {
        self.statuses = statuses
        self.minimumSeverity = minimumSeverity
    }

    public func includes(_ hotspot: Hotspot) -> Bool {
        statuses.contains(hotspot.status) && hotspot.severity >= minimumSeverity
    }
}

/// One of the eight compass directions, for "400 m NE" style directions.
public enum CompassPoint: String, CaseIterable, Sendable {
    case north = "N", northEast = "NE", east = "E", southEast = "SE"
    case south = "S", southWest = "SW", west = "W", northWest = "NW"

    /// The nearest point to a bearing in degrees clockwise from north.
    public init(degrees: Double) {
        let index = Int((degrees.normalizedDegrees / 45).rounded()) % 8
        self = Self.allCases[index]
    }
}
