import Foundation
import TestSupport
import Testing

@testable import FireWatchCore

struct FeedStoreTests {
    let clock = TestClock()
    var start: Date { Date(timeIntervalSince1970: 1_800_000_000) }

    func makeStore() -> FeedStore {
        let clock = clock
        return FeedStore(now: { clock.now })
    }

    func observed(_ id: Hotspot.ID, minute: Double, celsius: Double = 400) -> FeedEvent {
        .hotspotObserved(
            HotspotObservation(
                hotspotID: id, coordinate: .manavgat,
                reading: TemperatureReading(time: start.addingTimeInterval(minute * 60), celsius: celsius),
                confidence: 0.9, droneID: "drone-1"))
    }

    func command(_ action: HotspotAction, on id: Hotspot.ID = "hs-1") -> HotspotCommand {
        HotspotCommand(hotspotID: id, action: action, issuedAt: start)
    }

    @Test func snapshotReplacesStateAndStampsTimes() async {
        let store = makeStore()
        let snapshot = FireState(events: [observed("hs-1", minute: 0)])
        await store.apply(.events([observed("old", minute: 0)]))
        clock.advance(seconds: 5)
        await store.apply(.snapshot(snapshot, asOf: start.addingTimeInterval(60)))
        let current = await store.current
        #expect(current.fire == snapshot)
        #expect(current.asOf == start.addingTimeInterval(60))
        #expect(current.receivedAt == clock.now)
    }

    @Test func eventsAdvanceFeedTime() async {
        let store = makeStore()
        await store.apply(.events([observed("hs-1", minute: 3), observed("hs-2", minute: 7)]))
        let current = await store.current
        #expect(current.fire.hotspots.count == 2)
        #expect(current.asOf == start.addingTimeInterval(7 * 60))
    }

    @Test func pendingCommandsShowOnTopUntilCleared() async {
        let store = makeStore()
        await store.apply(.events([observed("hs-1", minute: 0)]))
        await store.setPending([command(.assign), command(.extinguish)])
        #expect(await store.current.fire.hotspots["hs-1"]?.status == .extinguished)
        #expect(await store.current.pendingCommands.count == 2)
        await store.setPending([])
        #expect(await store.current.fire.hotspots["hs-1"]?.status == .new)
    }

    @Test func pendingCommandsTheFeedMadeImpossibleStopShowing() async {
        let store = makeStore()
        await store.apply(.events([observed("hs-1", minute: 0)]))
        await store.setPending([command(.verifyCold)])  // not allowed from new
        #expect(await store.current.fire.hotspots["hs-1"]?.status == .new)
    }

    @Test func confirmedCommandIsNotAppliedTwice() async {
        let store = makeStore()
        let assign = command(.assign)
        await store.apply(.events([observed("hs-1", minute: 0), .hotspotCommandApplied(assign)]))
        await store.setPending([assign])  // the receipt hasn't arrived yet
        #expect(await store.current.fire.hotspots["hs-1"]?.status == .assigned)
    }

    @Test func connectionChangesArePublished() async {
        let store = makeStore()
        var states = store.states().makeAsyncIterator()
        #expect(await states.next()?.connection == .connecting)
        await store.apply(.connection(.live))
        #expect(await states.next()?.connection == .live)
    }

    @Test func followsAFeed() async throws {
        let store = makeStore()
        let snapshot = FireState(events: [observed("hs-1", minute: 0)])
        let following = Task { await store.follow(FixtureFeed(state: snapshot, asOf: start)) }
        var states = store.states().makeAsyncIterator()
        while let state = await states.next(), state.fire != snapshot {}
        #expect(await store.current.connection == .live)
        following.cancel()
    }
}

struct FeedStoreQueueTests {
    @Test func countsQueuedCommandsAndReports() async {
        let store = FeedStore()
        let command = HotspotCommand(hotspotID: "hs", action: .assign, issuedAt: .now)
        await store.setPending([command], queuedReports: 2)
        #expect(await store.current.queuedCount == 3)
        #expect(FieldState.empty.queuedCount == 0)
    }
}
