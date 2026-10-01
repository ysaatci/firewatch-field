import Foundation
import TestSupport
import Testing

@testable import FireWatchCore

struct HotspotClustererTests {
    let projection = LocalProjection(origin: .manavgat)

    func hotspot(_ id: Hotspot.ID, x: Double, y: Double = 0, celsius: Double = 100) -> Hotspot {
        Hotspot(
            id: id, coordinate: projection.unproject(PlanarPoint(x: x, y: y)), confidence: 0.9,
            reading: TemperatureReading(time: .distantPast, celsius: celsius))
    }

    @Test func nearbyHotspotsShareACell() {
        let hotspots = [hotspot("a", x: 10), hotspot("b", x: 60), hotspot("c", x: 900)]
        let clusters = HotspotClusterer(cellSize: 200).clusters(of: hotspots)
        #expect(clusters.map(\.members) == [["a", "b"], ["c"]])
        #expect(clusters[0].id == "a+b")
        #expect(clusters[0].count == 2)
    }

    @Test func clusterTakesTheWorstSeverityAndTheAveragePosition() throws {
        let clusters = HotspotClusterer(cellSize: 500).clusters(of: [
            hotspot("a", x: 100, celsius: 90), hotspot("b", x: 300, celsius: 450),
        ])
        let cluster = try #require(clusters.first)
        #expect(cluster.severity == .extreme)
        #expect(isClose(projection.project(cluster.coordinate).x, 200, within: 0.5))
    }

    @Test func smallCellsKeepEveryHotspotApart() {
        let hotspots = (0..<50).map { hotspot(Hotspot.ID("h\($0)"), x: Double($0) * 40) }
        #expect(HotspotClusterer(cellSize: 10).clusters(of: hotspots).count == 50)
    }

    @Test func noHotspotsNoClusters() {
        #expect(HotspotClusterer(cellSize: 100).clusters(of: [Hotspot]()).isEmpty)
    }

    @Test func cellSizeFollowsTheZoom() {
        #expect(HotspotClusterer.cellSize(forViewWidth: 4_000) == 500)
        #expect(HotspotClusterer(cellSize: 0).cellSize == 1)
    }

    @Test func handlesThousandsQuickly() {
        let hotspots = (0..<3_000).map {
            hotspot(Hotspot.ID("h\($0)"), x: Double($0 % 60) * 50, y: Double($0 / 60) * 50)
        }
        let started = ContinuousClock.now
        let clusters = HotspotClusterer(cellSize: 400).clusters(of: hotspots)
        #expect(clusters.reduce(0) { $0 + $1.count } == 3_000)
        #expect(ContinuousClock.now - started < .seconds(1))
    }
}
