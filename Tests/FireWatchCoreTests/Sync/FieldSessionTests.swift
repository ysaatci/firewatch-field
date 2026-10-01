import Foundation
import TestSupport
import Testing

@testable import FireWatchCore

struct FieldSessionTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let projection = LocalProjection(origin: .manavgat)

    func observed(_ id: Hotspot.ID, metresEast: Double = 300, minute: Double = 0) -> FeedEvent {
        .hotspotObserved(
            HotspotObservation(
                hotspotID: id, coordinate: projection.unproject(PlanarPoint(x: metresEast, y: 0)),
                reading: TemperatureReading(time: start.addingTimeInterval(minute * 60), celsius: 300),
                confidence: 0.9, droneID: "drone-1"))
    }

    func makeSession(feed: ManualFeed, sink: ScriptedSink) async -> FieldSession {
        let session = FieldSession(feed: feed, sink: sink, outboxStore: InMemoryOutboxStore())
        await session.start()
        try? await eventually { feed.hasSubscribers }
        return session
    }

    @Test func feedFillsTheStore() async throws {
        let feed = ManualFeed()
        let session = await makeSession(feed: feed, sink: ScriptedSink())
        feed.send(.snapshot(FireState(events: [observed("hs-1")]), asOf: start))
        try await eventually { await session.store.current.fire.hotspots["hs-1"] != nil }
        await session.stop()
    }

    @Test func actionsShowAtOnceAndAreSent() async throws {
        let feed = ManualFeed()
        let sink = ScriptedSink([.failure(.unavailable)])  // offline at first
        let session = await makeSession(feed: feed, sink: sink)
        feed.send(.snapshot(FireState(events: [observed("hs-1")]), asOf: start))
        try await eventually { await session.store.current.fire.hotspots["hs-1"] != nil }

        await session.perform(.assign, on: "hs-1")
        try await eventually { await session.store.current.fire.hotspots["hs-1"]?.status == .assigned }
        #expect(await session.store.current.pendingCommands.count == 1)

        feed.send(.connection(.live))  // back online: retry without waiting for the backoff
        try await eventually { await session.store.current.pendingCommands.isEmpty }
        #expect(await sink.sent.count == 2)
        await session.stop()
    }

    @Test func rejectionsAreReported() async throws {
        let feed = ManualFeed()
        let session = await makeSession(feed: feed, sink: ScriptedSink([.failure(.rejected("Not allowed"))]))
        var rejections = session.rejections().makeAsyncIterator()
        await session.perform(.verifyCold, on: "hs-1")
        let rejection = await rejections.next()
        #expect(rejection?.reason == "Not allowed")
        await session.stop()
    }

    @Test func nearbyChangesAlertOnce() async throws {
        let feed = ManualFeed()
        let session = await makeSession(feed: feed, sink: ScriptedSink())
        await session.setUserLocation(.manavgat)
        var alerts = session.alerts().makeAsyncIterator()
        feed.send(.snapshot(FireState(events: [observed("far", metresEast: 9_000)]), asOf: start))
        try await eventually { await session.store.current.fire.hotspots.count == 1 }
        feed.send(.events([observed("near", minute: 1)]))
        feed.send(.events([observed("near", minute: 2)]))  // the same hotspot again: no second alert
        feed.send(.events([observed("other", metresEast: 600, minute: 3)]))

        #expect(await alerts.next()?.hotspotID == "near")
        #expect(await alerts.next()?.hotspotID == "other")
        await session.stop()
    }
}
