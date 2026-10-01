/// Exponential backoff with full jitter: retry `n` (from 0) waits a random time up to
/// `min(cap, base × 2ⁿ)`. The randomness keeps a fleet of devices that lost signal
/// together from all reconnecting at the same instant.
public struct Backoff: Hashable, Sendable {
    public var base: Duration
    public var cap: Duration

    public init(base: Duration = .milliseconds(500), cap: Duration = .seconds(30)) {
        self.base = base
        self.cap = cap
    }

    /// The longest wait before retry `attempt`.
    public func ceiling(forAttempt attempt: Int) -> Duration {
        let doublings = min(max(attempt, 0), 30)  // 2³⁰ × base is far past any sensible cap
        return min(cap, base * (1 << doublings))
    }

    /// The wait before retry `attempt`, given a uniform `unit` in `0..<1`.
    public func delay(forAttempt attempt: Int, unit: Double) -> Duration {
        ceiling(forAttempt: attempt) * min(max(unit, 0), 1)
    }
}
