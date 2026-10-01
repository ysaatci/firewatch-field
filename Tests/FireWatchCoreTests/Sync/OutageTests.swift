import Foundation
import TestSupport
import Testing

@testable import FireWatchCore

struct OutageTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func sinkFailsAsUnavailableOnlyDuringTheOutage() async throws {
        let outage = Outage(active: true)
        let sink = OutageSink(wrapping: ScriptedSink(), outage: outage)
        let command = HotspotCommand(hotspotID: "hs", action: .assign, issuedAt: start)
        await #expect(throws: SubmissionError.unavailable) { try await sink.submit(command) }
        outage.isActive = false
        #expect(try await sink.submit(command) == .applied)
    }

    @Test func feedGoesOfflineAndResnapshotsWhenTheOutageEnds() async throws {
        let outage = Outage()
        let feed = OutageFeed(
            wrapping: FixtureFeed(state: FireState(), asOf: start), outage: outage, retryInterval: 5,
            now: { [start] in start })
        var updates = feed.updates().makeAsyncIterator()
        #expect(await updates.next() == .connection(.live))
        #expect(await updates.next() == .snapshot(FireState(), asOf: start))

        outage.isActive = true
        #expect(await updates.next() == .connection(.offline(retryAt: start.addingTimeInterval(5))))

        outage.isActive = false
        #expect(await updates.next() == .connection(.live))
        #expect(await updates.next() == .snapshot(FireState(), asOf: start))
    }

    @Test func statesStartWithTheCurrentValueAndSkipNonChanges() async {
        let outage = Outage(active: true)
        var states = outage.states().makeAsyncIterator()
        #expect(await states.next() == true)
        outage.isActive = true  // no change: nothing sent
        outage.isActive = false
        #expect(await states.next() == false)
    }
}
