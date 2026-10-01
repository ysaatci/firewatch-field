import Foundation
import TestSupport
import Testing

@testable import FireWatchCore

struct BackoffTests {
    let backoff = Backoff(base: .milliseconds(500), cap: .seconds(30))

    @Test func ceilingDoublesUpToTheCap() {
        let ceilings = (0..<8).map { backoff.ceiling(forAttempt: $0) }
        #expect(ceilings.prefix(4) == [.milliseconds(500), .seconds(1), .seconds(2), .seconds(4)])
        #expect(ceilings.last == .seconds(30))
        #expect(backoff.ceiling(forAttempt: 1_000) == .seconds(30))
    }

    @Test func jitterSpreadsWithinTheCeiling() {
        #expect(backoff.delay(forAttempt: 3, unit: 0) == .zero)
        #expect(backoff.delay(forAttempt: 3, unit: 0.5) == .seconds(2))
        #expect(backoff.delay(forAttempt: 3, unit: 5) == .seconds(4))
    }

    @Test func durationSeconds() {
        #expect(Duration.milliseconds(1_500).seconds == 1.5)
    }
}

struct ReconnectingSocketTests {
    let clock = TestClock()

    /// Collects `count` events, recording requested sleeps without actually waiting.
    func events(_ steps: [ScriptedConnector.Step], count: Int) async -> (
        events: [ReconnectingSocket.Event], sleeps: [Duration]
    ) {
        let recorder = SleepRecorder()
        let socket = ReconnectingSocket(
            connector: ScriptedConnector(steps),
            backoff: Backoff(base: .seconds(1), cap: .seconds(8)),
            now: { [clock] in clock.now },
            random: { 0.5 },
            sleep: { await recorder.record($0) }
        )
        var collected: [ReconnectingSocket.Event] = []
        for await event in socket.events().prefix(count) { collected.append(event) }
        return (collected, await recorder.sleeps)
    }

    actor SleepRecorder {
        var sleeps: [Duration] = []
        func record(_ duration: Duration) { sleeps.append(duration) }
    }

    @Test func deliversMessagesThenReconnectsWhenClosed() async {
        let (events, _) = await events([.connect(["a", "b"]), .connect(["c"])], count: 6)
        #expect(
            events == [
                .connected, .message("a"), .message("b"),
                .disconnected(retryAt: clock.now.addingTimeInterval(0.5)),
                .connected, .message("c"),
            ])
    }

    @Test func backsOffAfterRepeatedFailuresAndResetsOnSuccess() async {
        let (events, sleeps) = await events([.fail, .fail, .fail, .connect([])], count: 5)
        let retries = [0.5, 1, 2].map {
            ReconnectingSocket.Event.disconnected(retryAt: clock.now.addingTimeInterval($0))
        }
        // Half of 1, 2, 4 s while failing; back to half of 1 s after the successful connect.
        #expect(events == retries + [.connected, .disconnected(retryAt: clock.now.addingTimeInterval(0.5))])
        #expect(sleeps.prefix(3) == [.milliseconds(500), .seconds(1), .seconds(2)])
    }
}
