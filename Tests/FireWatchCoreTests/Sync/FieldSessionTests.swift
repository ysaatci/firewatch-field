import Foundation
import TestSupport
import Testing

@testable import FireWatchCore

// A hung async test fails by name instead of stalling the whole run.
@Suite(.timeLimit(.minutes(1)))
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
        // States reach the session newest-first, and the first fire it sees never alerts (a cold
        // start), so wait until the snapshot is its baseline.
        try await eventually { await session.lastFire.hotspots.count == 1 }
        feed.send(.events([observed("near", minute: 1)]))
        feed.send(.events([observed("near", minute: 2)]))  // the same hotspot again: no second alert
        feed.send(.events([observed("other", metresEast: 600, minute: 3)]))

        #expect(await alerts.next()?.hotspotID == "near")
        #expect(await alerts.next()?.hotspotID == "other")
        await session.stop()
    }
}

// A hung async test fails by name instead of stalling the whole run.
@Suite(.timeLimit(.minutes(1)))
struct FieldSessionCacheTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let clock = TestClock()

    func observed(_ id: Hotspot.ID, minute: Double) -> FeedEvent {
        .hotspotObserved(
            HotspotObservation(
                hotspotID: id, coordinate: .manavgat,
                reading: TemperatureReading(time: start.addingTimeInterval(minute * 60), celsius: 300),
                confidence: 0.9, droneID: "drone-1"))
    }

    func makeSession(feed: ManualFeed, cache: InMemoryFieldCache) -> FieldSession {
        let clock = clock
        return FieldSession(
            feed: feed, sink: ScriptedSink(), outboxStore: InMemoryOutboxStore(), cache: cache, cacheInterval: 30,
            now: { clock.now })
    }

    @Test func opensWithTheCachedStateBeforeTheFeedAnswers() async throws {
        let cached = CachedFire(state: FireState(events: [observed("hs-1", minute: 0)]), asOf: start, receivedAt: start)
        let session = makeSession(feed: ManualFeed(), cache: InMemoryFieldCache(cached))
        await session.start()
        let current = await session.store.current
        #expect(current.fire.hotspots["hs-1"] != nil)
        #expect(current.connection == .connecting)
        #expect(current.receivedAt == start)
        await session.stop()
    }

    @Test func savesTheFeedStateAtMostOncePerInterval() async throws {
        let feed = ManualFeed()
        let cache = InMemoryFieldCache()
        let session = makeSession(feed: feed, cache: cache)
        await session.start()
        try await eventually { feed.hasSubscribers }

        feed.send(.snapshot(FireState(events: [observed("hs-1", minute: 0)]), asOf: start))
        try await eventually { await cache.saveCount == 1 }
        feed.send(.events([observed("hs-2", minute: 1)]))  // within the interval: not saved
        try await eventually { await session.store.current.fire.hotspots["hs-2"] != nil }
        #expect(await cache.saveCount == 1)
        clock.advance(seconds: 31)
        feed.send(.events([observed("hs-3", minute: 2)]))
        try await eventually { await cache.saveCount == 2 }
        // The save holds the store's latest state, which has hs-2 by now and may already have hs-3.
        #expect(await cache.saved?.state.hotspots["hs-2"] != nil)
        await session.stop()
    }

    @Test func pendingCommandsAreNotCachedAsFact() async throws {
        let feed = ManualFeed()
        let cache = InMemoryFieldCache()
        let session = FieldSession(
            feed: feed, sink: ScriptedSink([.failure(.unavailable)]), outboxStore: InMemoryOutboxStore(),
            cache: cache)
        await session.start()
        try await eventually { feed.hasSubscribers }
        feed.send(.snapshot(FireState(events: [observed("hs-1", minute: 0)]), asOf: start))
        await session.perform(.assign, on: "hs-1")
        try await eventually { await session.store.current.fire.hotspots["hs-1"]?.status == .assigned }

        await session.saveCache()
        #expect(await cache.saved?.state.hotspots["hs-1"]?.status == .new)
        await session.stop()
    }
}
