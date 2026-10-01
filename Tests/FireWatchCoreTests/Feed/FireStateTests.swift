import Foundation
import TestSupport
import Testing

@testable import FireWatchCore

struct FireStateTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    func observed(_ id: Hotspot.ID, celsius: Double, minute: Double) -> FeedEvent {
        .hotspotObserved(
            HotspotObservation(
                hotspotID: id,
                coordinate: .manavgat,
                reading: TemperatureReading(time: at(minute), celsius: celsius),
                confidence: 0.9,
                droneID: "drone-1"
            ))
    }

    func command(_ action: HotspotAction, on id: Hotspot.ID = "hs-1", minute: Double) -> HotspotCommand {
        HotspotCommand(hotspotID: id, action: action, issuedAt: at(minute))
    }

    @Test func firstObservationCreatesHotspot() throws {
        let state = FireState(events: [observed("hs-1", celsius: 400, minute: 0)])
        let hotspot = try #require(state.hotspots["hs-1"])
        #expect(hotspot.temperatureCelsius == 400)
        #expect(hotspot.status == .new)
    }

    @Test func laterObservationsUpdateReadings() throws {
        let state = FireState(events: [
            observed("hs-1", celsius: 400, minute: 0), observed("hs-1", celsius: 250, minute: 5),
        ])
        let hotspot = try #require(state.hotspots["hs-1"])
        #expect(hotspot.readings.map(\.celsius) == [400, 250])
    }

    @Test func executesLegalCommands() throws {
        var state = FireState(events: [observed("hs-1", celsius: 400, minute: 0)])
        let assign = command(.assign, minute: 1)
        let event = try state.execute(assign)
        #expect(event == .hotspotCommandApplied(assign))
        #expect(state.hotspots["hs-1"]?.status == .assigned)
    }

    @Test func rejectsIllegalAndUnknownCommands() {
        var state = FireState(events: [observed("hs-1", celsius: 400, minute: 0)])
        #expect(throws: CommandRejection.notAllowed(WorkflowError(action: .verifyCold, status: .new))) {
            try state.execute(command(.verifyCold, minute: 1))
        }
        #expect(throws: CommandRejection.unknownHotspot("nope")) {
            try state.execute(command(.assign, on: "nope", minute: 1))
        }
        #expect(state.hotspots["hs-1"]?.status == .new)
    }

    @Test func hotReadingAfterExtinguishFlaresUp() throws {
        let state = FireState(events: [
            observed("hs-1", celsius: 400, minute: 0),
            .hotspotCommandApplied(command(.extinguish, minute: 10)),
            observed("hs-1", celsius: 40, minute: 20),
            observed("hs-1", celsius: 280, minute: 90),
        ])
        let hotspot = try #require(state.hotspots["hs-1"])
        #expect(hotspot.status == .flaredUp)
        #expect(hotspot.workflow.flareUps == 1)
    }

    @Test func hotReadingOnOpenHotspotIsJustAReading() {
        let state = FireState(events: [
            observed("hs-1", celsius: 100, minute: 0), observed("hs-1", celsius: 500, minute: 5),
        ])
        #expect(state.hotspots["hs-1"]?.status == .new)
    }

    @Test func staleHotReadingDoesNotFlareUp() {
        let state = FireState(events: [
            observed("hs-1", celsius: 400, minute: 10),
            .hotspotCommandApplied(command(.extinguish, minute: 11)),
            observed("hs-1", celsius: 400, minute: 5),  // arrived late
        ])
        #expect(state.hotspots["hs-1"]?.status == .extinguished)
    }

    @Test func perimetersStayInTimeOrder() {
        let state = FireState(events: [
            .perimeterUpdated(FirePerimeter(time: at(10), polygons: [])),
            .perimeterUpdated(FirePerimeter(time: at(5), polygons: [])),
            .perimeterUpdated(FirePerimeter(time: at(15), polygons: [])),
        ])
        #expect(state.perimeters.map(\.time) == [at(10), at(15)])
        #expect(state.latestPerimeter?.time == at(15))
    }

    @Test func droneUpdatesCreateThenMove() throws {
        func moved(_ minute: Double) -> FeedEvent {
            .droneMoved(
                DroneUpdate(
                    droneID: "drone-1",
                    name: "Kartal-1",
                    position: DronePosition(
                        time: at(minute), coordinate: .manavgat, headingDegrees: 0, altitudeMetres: 120, battery: 1)
                ))
        }
        let state = FireState(events: [moved(0), moved(1)])
        let drone = try #require(state.drones["drone-1"])
        #expect(drone.track.count == 2)
        #expect(drone.name == "Kartal-1")
    }

    @Test func eventTimes() {
        let assign = command(.assign, minute: 3)
        #expect(observed("hs-1", celsius: 1, minute: 2).time == at(2))
        #expect(FeedEvent.hotspotCommandApplied(assign).time == at(3))
        #expect(FeedEvent.perimeterUpdated(FirePerimeter(time: at(4), polygons: [])).time == at(4))
    }
}
