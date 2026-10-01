import Foundation
import Testing

@testable import FireWatchCore

struct PriorityRankerTests {
    let ranker = PriorityRanker()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let projection = LocalProjection(origin: .manavgat)

    func hotspot(
        _ id: Hotspot.ID,
        celsius: Double = 300,
        minutesAgo: Double = 0,
        metresEast: Double = 0,
        after actions: [HotspotAction] = []
    ) throws -> Hotspot {
        Hotspot(
            id: id,
            coordinate: projection.unproject(PlanarPoint(x: metresEast, y: 0)),
            confidence: 0.9,
            reading: TemperatureReading(time: now.addingTimeInterval(-minutesAgo * 60), celsius: celsius),
            workflow: try actions.reduce(.initial) { try $0.applying($1) }
        )
    }

    func order(_ hotspots: [Hotspot], user: Coordinate? = .manavgat) -> [Hotspot.ID] {
        ranker.ranked(hotspots, now: now, userLocation: user).map(\.id)
    }

    @Test func hotterFirst() throws {
        #expect(try order([hotspot("cool", celsius: 90), hotspot("hot", celsius: 450)]) == ["hot", "cool"])
    }

    @Test func recentFirstWhenEquallyHot() throws {
        #expect(
            try order([hotspot("old", minutesAgo: 90), hotspot("fresh", minutesAgo: 1)]) == ["fresh", "old"])
    }

    @Test func nearerFirstWhenOtherwiseEqual() throws {
        #expect(
            try order([hotspot("far", metresEast: 5_000), hotspot("near", metresEast: 200)]) == [
                "near", "far",
            ])
    }

    @Test func distanceIgnoredWithoutUserLocation() throws {
        let hotspots = try [hotspot("b", metresEast: 5_000), hotspot("a", metresEast: 200)]
        #expect(order(hotspots, user: nil) == ["a", "b"])
    }

    @Test func handledHotspotsSink() throws {
        let hotspots = try [
            hotspot("cold", celsius: 500, after: [.extinguish, .verifyCold]),
            hotspot("put-out", celsius: 500, after: [.extinguish]),
            hotspot("taken", celsius: 500, after: [.assign]),
            hotspot("open", celsius: 150),
        ]
        #expect(order(hotspots) == ["taken", "open", "put-out", "cold"])
    }

    @Test func flareUpsRankLikeNewHotspots() throws {
        let flared = try hotspot("flared", after: [.extinguish, .flareUp])
        let fresh = try hotspot("fresh")
        #expect(
            ranker.score(of: flared, now: now, userLocation: nil)
                == ranker.score(of: fresh, now: now, userLocation: nil))
    }

    @Test func tiesBreakByID() throws {
        #expect(try order([hotspot("b"), hotspot("c"), hotspot("a")]) == ["a", "b", "c"])
    }

    @Test func scoresStayInUnitRange() throws {
        for spot in try [hotspot("x", celsius: 2_000), hotspot("y", celsius: -10, minutesAgo: -5)] {
            let score = ranker.score(of: spot, now: now, userLocation: .manavgat)
            #expect((0...1).contains(score))
        }
    }
}
