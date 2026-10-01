import FireWatchCore
import Foundation
import TestSupport
import Testing

@testable import FireWatchSimulator

struct DroneSurveyTests {
    let terrain = TerrainGrid(
        cellSize: 50,
        centre: Coordinate(latitude: 36.787, longitude: 31.443),
        fuel: Grid(rows: 60, columns: 60, repeating: 1),
        elevation: Grid(rows: 60, columns: 60, repeating: 0)
    )
    let survey = DroneSurvey()

    func hotspot(at point: PlanarPoint, appearsAt minute: Double = 0, peak: Double = 300) -> ResidualHotspot {
        ResidualHotspot(
            id: "hs",
            coordinate: terrain.projection.unproject(point),
            smoulder: CoolingCurve(startMinute: minute, peakCelsius: peak, coolingMinutes: 1_000),
            flareUp: nil
        )
    }

    @Test func routesSplitTheAreaAndStayInside() {
        let routes = survey.routes(over: terrain)
        #expect(routes.count == 3)
        #expect(Set(routes.map(\.droneID)).count == 3)
        #expect(routes.map(\.name) == ["Kartal-1", "Şahin-2", "Doğan-3"])
        for route in routes {
            #expect(route.waypoints.allSatisfy { abs($0.x) <= 1_500 && abs($0.y) <= 1_500 })
        }
        // Strips don't overlap: each drone's lanes are west of the next drone's.
        let eastEdges = routes.map { $0.waypoints.map(\.x).max() ?? 0 }
        let westEdges = routes.map { $0.waypoints.map(\.x).min() ?? 0 }
        #expect(zip(eastEdges, westEdges.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test func flightFollowsRouteBackAndForth() throws {
        let route = try #require(survey.routes(over: terrain).first)
        let start = route.location(atSecond: 0)
        #expect(start.point == route.waypoints[0])
        #expect(isClose(start.headingDegrees, 0, within: 1e-9))  // first lane flies north
        let atEnd = route.location(atSecond: route.length / route.speed)
        #expect(isClose(atEnd.point.x, route.waypoints[route.waypoints.count - 1].x, within: 1e-6))
        let backHome = route.location(atSecond: 2 * route.length / route.speed - 1)
        #expect(hypot(backHome.point.x - start.point.x, backHome.point.y - start.point.y) <= route.speed + 1e-6)
    }

    @Test func batteryDrainsAndSwaps() throws {
        let route = try #require(survey.routes(over: terrain).first)
        #expect(route.battery(atSecond: 0) == 1)
        #expect(isClose(route.battery(atSecond: 20 * 60), 0.6, within: 1e-9))
        #expect(route.battery(atSecond: 40 * 60) == 1)
    }

    @Test func detectsOnlyHotspotsUnderTheFootprint() {
        let routes = survey.routes(over: terrain)
        let underFirstLane = routes[0].waypoints[0]
        let spots = [
            hotspot(at: PlanarPoint(x: underFirstLane.x + 50, y: 0)),
            hotspot(at: PlanarPoint(x: underFirstLane.x, y: 0), peak: 45),  // too cool to detect
        ]
        let passes = survey.passes(of: spots, routes: routes, terrain: terrain, minutes: 10, ambientCelsius: 30)
        #expect(!passes.isEmpty)
        #expect(passes.allSatisfy { $0.hotspot == 0 && $0.distance <= survey.footprintRadius })
        #expect(passes.first?.droneID == routes[0].droneID)
    }

    @Test func revisitsAreSpacedAndInTimeOrder() {
        let routes = survey.routes(over: terrain)
        let spots = [hotspot(at: routes[1].waypoints[0])]
        let passes = survey.passes(of: spots, routes: routes, terrain: terrain, minutes: 180, ambientCelsius: 30)
        #expect(passes.count > 2)
        let minutes = passes.map(\.minute)
        #expect(minutes == minutes.sorted())
        #expect(zip(minutes, minutes.dropFirst()).allSatisfy { $1 - $0 >= survey.revisitMinutes })
    }

    @Test func notSeenBeforeItAppears() {
        let routes = survey.routes(over: terrain)
        let spots = [hotspot(at: routes[0].waypoints[0], appearsAt: 60)]
        let passes = survey.passes(of: spots, routes: routes, terrain: terrain, minutes: 120, ambientCelsius: 30)
        #expect(passes.allSatisfy { $0.minute >= 60 })
    }
}
