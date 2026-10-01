/// Hotspots close enough together on screen to draw as one marker.
public struct HotspotCluster: Hashable, Sendable, Identifiable {
    /// Stable while the members stay the same, so map selection survives updates.
    public let id: String
    /// Average position of the members.
    public let coordinate: Coordinate
    /// Member IDs in ID order.
    public let members: [Hotspot.ID]
    /// The worst member, so a cluster never hides how dangerous its hotspots are.
    public let severity: Severity

    public var count: Int { members.count }
}

/// Groups hotspots into square cells of a given size: a grid clusterer, chosen because it is
/// fast, stable as the map pans, and simple to reason about (NFR-2).
public struct HotspotClusterer: Sendable {
    /// Cell width in metres; the map sets it from the zoom level.
    public var cellSize: Double

    public init(cellSize: Double) {
        self.cellSize = max(cellSize, 1)
    }

    /// A cell size giving about `cellsAcross` clusters across a view `metresAcross` wide.
    public static func cellSize(forViewWidth metresAcross: Double, cellsAcross: Double = 8) -> Double {
        metresAcross / cellsAcross
    }

    public func clusters(of hotspots: some Collection<Hotspot>) -> [HotspotCluster] {
        guard let origin = hotspots.first?.coordinate else { return [] }
        let projection = LocalProjection(origin: origin)
        var cells: [GridKey: [Hotspot]] = [:]
        for hotspot in hotspots {
            let point = projection.project(hotspot.coordinate)
            let key = GridKey(x: Int((point.x / cellSize).rounded(.down)), y: Int((point.y / cellSize).rounded(.down)))
            cells[key, default: []].append(hotspot)
        }
        return cells.values
            .map { members in
                let sorted = members.sorted { $0.id < $1.id }
                let latitude = sorted.reduce(0) { $0 + $1.coordinate.latitude } / Double(sorted.count)
                let longitude = sorted.reduce(0) { $0 + $1.coordinate.longitude } / Double(sorted.count)
                return HotspotCluster(
                    id: sorted.map(\.id.rawValue).joined(separator: "+"),
                    coordinate: Coordinate(latitude: latitude, longitude: longitude),
                    members: sorted.map(\.id),
                    severity: sorted.map(\.severity).max() ?? .low
                )
            }
            .sorted { $0.id < $1.id }
    }

    private struct GridKey: Hashable {
        var x: Int
        var y: Int
    }
}
