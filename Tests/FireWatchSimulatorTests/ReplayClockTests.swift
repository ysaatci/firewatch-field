import Foundation
import Testing

@testable import FireWatchSimulator

struct ReplayClockTests {
    let start = Date(timeIntervalSince1970: 1_000)

    func after(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    @Test func runsAtSpeed() {
        let clock = ReplayClock(startMinute: 10, endMinute: 240, speed: 60, now: start)
        #expect(clock.minute(at: start) == 10)
        #expect(clock.minute(at: after(30)) == 40)  // 30 s × 60 = 30 scenario minutes
    }

    @Test func pauseFreezesAndStartResumes() {
        var clock = ReplayClock(startMinute: 0, endMinute: 240, speed: 60, now: start)
        clock.pause(at: after(10))
        #expect(clock.minute(at: after(100)) == 10)
        clock.start(at: after(100))
        #expect(clock.minute(at: after(105)) == 15)
    }

    @Test func speedChangesOnlyAffectTheFuture() {
        var clock = ReplayClock(startMinute: 0, endMinute: 240, speed: 60, now: start)
        clock.setSpeed(120, at: after(10))
        #expect(clock.minute(at: after(10)) == 10)
        #expect(clock.minute(at: after(20)) == 30)
    }

    @Test func stopsAtTheEnd() {
        let clock = ReplayClock(startMinute: 230, endMinute: 240, speed: 60, now: start)
        #expect(clock.minute(at: after(3_600)) == 240)
        #expect(clock.isFinished(at: after(3_600)))
        #expect(!clock.isFinished(at: start))
    }

    @Test func neverRunsBackwards() {
        let clock = ReplayClock(startMinute: 5, endMinute: 240, speed: 60, now: start)
        #expect(clock.minute(at: after(-100)) == 5)
    }
}
