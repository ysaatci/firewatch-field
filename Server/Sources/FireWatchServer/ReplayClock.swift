import Foundation

/// Maps real time to scenario time: runs at a chosen speed, pauses, and stops at the end.
///
/// A value type driven by explicit `now` dates, so it is trivially testable.
struct ReplayClock: Hashable, Sendable {
    private(set) var isRunning: Bool
    /// Scenario seconds per real second.
    private(set) var speed: Double
    let endMinute: Double
    /// Scenario minute at `anchor`; the clock counts on from there.
    private var anchorMinute: Double
    private var anchor: Date

    init(startMinute: Double, endMinute: Double, speed: Double, now: Date, running: Bool = true) {
        self.isRunning = running
        self.speed = speed
        self.endMinute = endMinute
        self.anchorMinute = min(startMinute, endMinute)
        self.anchor = now
    }

    func minute(at now: Date) -> Double {
        guard isRunning else { return anchorMinute }
        let elapsedRealSeconds = max(now.timeIntervalSince(anchor), 0)
        return min(anchorMinute + elapsedRealSeconds * speed / 60, endMinute)
    }

    func isFinished(at now: Date) -> Bool {
        minute(at: now) >= endMinute
    }

    mutating func start(at now: Date) {
        reanchor(at: now)
        isRunning = true
    }

    mutating func pause(at now: Date) {
        reanchor(at: now)
        isRunning = false
    }

    mutating func setSpeed(_ speed: Double, at now: Date) {
        reanchor(at: now)
        self.speed = speed
    }

    /// Restarts counting from the current scenario minute, so later changes only affect the future.
    private mutating func reanchor(at now: Date) {
        anchorMinute = minute(at: now)
        anchor = now
    }
}
