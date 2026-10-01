import FireWatchCore
import Foundation
import Testing

@testable import FireWatchSimulator

struct ReplaySessionTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func after(_ seconds: Double) -> Date { now.addingTimeInterval(seconds) }

    func makeSession(startMinute: Double = 60, speed: Double = 60) -> ReplaySession {
        ReplaySession(
            scenario: ScenarioTests.scenario, preset: .manavgat, speed: speed, startMinute: startMinute, now: now)
    }

    /// The hottest detected hotspot, which drones keep observing.
    func hottest(_ session: ReplaySession) throws -> Hotspot {
        try #require(session.state.hotspots.values.max { $0.temperatureCelsius < $1.temperatureCelsius })
    }

    @Test func startsWithHistoryAndScenarioTimeAtNow() {
        let session = makeSession()
        #expect(session.state.drones.count == 3)
        #expect(session.state.latestPerimeter != nil)
        #expect(session.scenarioNow == now)
        #expect(session.status(at: now).phase == .running)
        #expect(session.status(at: now).scenarioMinute == 60)
    }

    @Test func advanceReturnsEachEventOnce() {
        var session = makeSession(startMinute: 0)
        var events: [FeedEvent] = []
        for step in 1...20 { events += session.advance(to: after(Double(step) * 7)) }
        #expect(session.advance(to: after(140)).isEmpty)
        #expect(events == session.world.events(fromMinute: 0, toMinute: 140))
        #expect(session.state == FireState(events: events))
    }

    @Test func pauseStopsTime() {
        var session = makeSession()
        session.pause(at: now)
        #expect(session.advance(to: after(600)).isEmpty)
        #expect(session.status(at: after(600)).phase == .paused)
        session.start(at: after(600))
        session.setSpeed(120, at: after(600))
        _ = session.advance(to: after(630))
        #expect(session.emittedMinute == 120)
    }

    @Test func commandsAreStampedWithScenarioTimeAndIdempotent() throws {
        var session = makeSession()
        _ = session.advance(to: after(30))
        let hotspot = try hottest(session)
        let command = HotspotCommand(hotspotID: hotspot.id, action: .assign, issuedAt: .distantPast)

        let first = try session.execute(command)
        #expect(first.outcome == .applied)
        guard case .hotspotCommandApplied(let applied)? = first.event else {
            Issue.record("expected an applied command event")
            return
        }
        #expect(applied.issuedAt == session.scenarioNow)
        #expect(try session.execute(command).outcome == .duplicate)
        #expect(session.state.hotspots[hotspot.id]?.status == .assigned)
    }

    @Test func rejectedCommandsCanBeRetried() throws {
        var session = makeSession()
        let hotspot = try hottest(session)
        let verify = HotspotCommand(hotspotID: hotspot.id, action: .verifyCold, issuedAt: now)
        #expect(throws: CommandRejection.self) { try session.execute(verify) }
        _ = try session.execute(HotspotCommand(hotspotID: hotspot.id, action: .extinguish, issuedAt: now))
        #expect(try session.execute(verify).outcome == .applied)
    }

    @Test func reportsAreIdempotent() {
        var session = makeSession()
        let report = SightingReport(
            createdAt: now, coordinate: Coordinate(latitude: 0, longitude: 0), severity: .low, note: "")
        #expect(session.submit(report) == .applied)
        #expect(session.submit(report) == .duplicate)
    }

    @Test func resetStartsOverAndForgetsCrews() throws {
        var session = makeSession()
        let hotspot = try hottest(session)
        let command = HotspotCommand(hotspotID: hotspot.id, action: .assign, issuedAt: now)
        _ = try session.execute(command)
        _ = session.advance(to: after(600))

        session.reset(to: ScenarioTests.scenario, preset: .manavgat, at: after(600))
        #expect(session.status(at: after(600)).scenarioMinute == 60)
        #expect(session.state.hotspots[hotspot.id]?.status == .new)
        #expect(try session.execute(command).outcome == .applied)
        #expect(session.status(at: after(600)).speed == 60)
    }
}
