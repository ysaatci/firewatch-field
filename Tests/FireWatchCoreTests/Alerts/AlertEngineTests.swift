import Foundation
import TestSupport
import Testing

@testable import FireWatchCore

struct AlertEngineTests {
    let engine = AlertEngine(radiusMetres: 2_000)
    let projection = LocalProjection(origin: .manavgat)
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func observed(_ id: Hotspot.ID, metresEast: Double, minute: Double = 0, celsius: Double = 300) -> FeedEvent {
        .hotspotObserved(
            HotspotObservation(
                hotspotID: id, coordinate: projection.unproject(PlanarPoint(x: metresEast, y: 0)),
                reading: TemperatureReading(time: start.addingTimeInterval(minute * 60), celsius: celsius),
                confidence: 0.9, droneID: "drone-1"))
    }

    /// A state that already knows one far-away hotspot, so it isn't a cold start.
    var known: [FeedEvent] { [observed("far", metresEast: 10_000)] }

    @Test func newNearbyHotspotsAlertNearestFirst() {
        let old = FireState(events: known)
        let new = FireState(events: known + [observed("b", metresEast: 1_500), observed("a", metresEast: 300)])
        let alerts = engine.alerts(from: old, to: new, near: .manavgat)
        #expect(alerts.map(\.hotspotID) == ["a", "b"])
        #expect(alerts.allSatisfy { $0.kind == .newHotspot })
        #expect(isClose(alerts[0].distanceMetres, 300, within: 1))
        #expect(alerts[0].severity == .high)
    }

    @Test func farHotspotsDoNotAlert() {
        let new = FireState(events: known + [observed("x", metresEast: 2_500)])
        #expect(engine.alerts(from: FireState(events: known), to: new, near: .manavgat).isEmpty)
    }

    @Test func flareUpsAlertEachTime() throws {
        let extinguish = FeedEvent.hotspotCommandApplied(
            HotspotCommand(hotspotID: "a", action: .extinguish, issuedAt: start.addingTimeInterval(60)))
        let before = known + [observed("a", metresEast: 500), extinguish]
        let flared = before + [observed("a", metresEast: 500, minute: 30, celsius: 350)]
        let alerts = engine.alerts(from: FireState(events: before), to: FireState(events: flared), near: .manavgat)
        let alert = try #require(alerts.first)
        #expect(alerts.count == 1)
        #expect(alert.kind == .flareUp)
        #expect(alert.id == "flareUp/a/1")
    }

    @Test func ordinaryReadingsDoNotAlert() {
        let old = FireState(events: known + [observed("a", metresEast: 500)])
        let new = FireState(
            events: known + [observed("a", metresEast: 500), observed("a", metresEast: 500, minute: 5)])
        #expect(engine.alerts(from: old, to: new, near: .manavgat).isEmpty)
    }

    @Test func noLocationOrColdStartMeansNoAlerts() {
        let new = FireState(events: known + [observed("a", metresEast: 100)])
        #expect(engine.alerts(from: FireState(events: known), to: new, near: nil).isEmpty)
        #expect(engine.alerts(from: FireState(), to: new, near: .manavgat).isEmpty)
    }
}
