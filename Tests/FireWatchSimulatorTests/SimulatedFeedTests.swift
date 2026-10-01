import FireWatchCore
import Foundation
import TestSupport
import Testing

@testable import FireWatchSimulator

struct SimulatedFeedTests {
    let clock = TestClock()
    let sleeper = ManualSleeper()

    func makeFeed() -> SimulatedFeed {
        let clock = clock
        let sleeper = sleeper
        return SimulatedFeed(speed: 60, startMinute: 60, now: { clock.now }, sleep: { try await sleeper.sleep($0) })
    }

    @Test func startsLiveWithASnapshot() async throws {
        let feed = makeFeed()
        var updates = feed.updates().makeAsyncIterator()
        #expect(await updates.next() == .connection(.live))
        guard case .snapshot(let state, let asOf)? = await updates.next() else {
            Issue.record("expected a snapshot")
            return
        }
        #expect(!state.hotspots.isEmpty)
        #expect(asOf == clock.now)
    }

    @Test func eachTickSendsWhatHappened() async throws {
        let feed = makeFeed()
        var updates = feed.updates().makeAsyncIterator()
        _ = await updates.next()
        _ = await updates.next()

        let start = clock.now
        clock.advance(seconds: 30)  // 30 scenario minutes at 60x
        await sleeper.release()
        guard case .events(let events)? = await updates.next() else {
            Issue.record("expected events")
            return
        }
        #expect(!events.isEmpty)
        #expect(events.allSatisfy { $0.time >= start && $0.time < start.addingTimeInterval(30 * 60) })
    }

    @Test func commandsAreAppliedAndShared() async throws {
        let feed = makeFeed()
        var updates = feed.updates().makeAsyncIterator()
        _ = await updates.next()
        guard case .snapshot(let state, _)? = await updates.next(), let hotspot = state.hotspots.keys.min() else {
            Issue.record("expected a snapshot with hotspots")
            return
        }
        let command = HotspotCommand(hotspotID: hotspot, action: .assign, issuedAt: .now)
        #expect(try await feed.submit(command) == .applied)
        guard case .events(let events)? = await updates.next(), events.count == 1,
            case .hotspotCommandApplied(let applied) = events[0]
        else {
            Issue.record("expected the applied command")
            return
        }
        #expect(applied.id == command.id)
        #expect(try await feed.submit(command) == .duplicate)
    }

    @Test func illegalCommandsAreRejectedWithAReason() async throws {
        let feed = makeFeed()
        let command = HotspotCommand(hotspotID: "hs-nowhere", action: .assign, issuedAt: .now)
        await #expect(throws: SubmissionError.rejected("No hotspot hs-nowhere has been detected")) {
            try await feed.submit(command)
        }
    }

    @Test func reportsAreAccepted() async {
        let feed = makeFeed()
        let report = SightingReport(createdAt: .now, coordinate: .manavgat, severity: .moderate, note: "")
        #expect(await feed.submit(report) == .applied)
        #expect(await feed.submit(report) == .duplicate)
    }

    @Test func fixtureFeedServesItsStateAndAcceptsEverything() async throws {
        let feed = FixtureFeed(state: FireState(), asOf: clock.now)
        var updates = feed.updates().makeAsyncIterator()
        #expect(await updates.next() == .connection(.live))
        #expect(await updates.next() == .snapshot(FireState(), asOf: clock.now))
        let command = HotspotCommand(hotspotID: "x", action: .assign, issuedAt: .now)
        #expect(try await feed.submit(command) == .applied)
    }
}
