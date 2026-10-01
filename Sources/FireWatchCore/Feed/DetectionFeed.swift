import Foundation

/// Where fire data comes from: the simulator on this device, the simulator server, and later
/// the real drone pipeline. The app only sees this protocol, so sources swap freely (D7).
public protocol DetectionFeed: Sendable {
    /// Connects and delivers updates until the stream is cancelled. Starts with a
    /// ``FeedUpdate/snapshot(_:asOf:)``, and sends a fresh one after every reconnect.
    func updates() -> AsyncStream<FeedUpdate>
}

/// Something a feed tells its subscriber.
public enum FeedUpdate: Hashable, Sendable {
    /// Everything known, replacing what came before. `asOf` is the feed's (scenario) time.
    case snapshot(FireState, asOf: Date)
    /// What happened since the last update, in time order.
    case events([FeedEvent])
    case connection(ConnectionStatus)
}

/// Whether the feed is getting through.
public enum ConnectionStatus: Hashable, Sendable {
    case connecting
    case live
    /// Lost; the next attempt is due at `retryAt`.
    case offline(retryAt: Date)
}

/// Where crew commands and sighting reports go.
public protocol CommandSink: Sendable {
    func submit(_ command: HotspotCommand) async throws(SubmissionError) -> SubmissionOutcome
    func submit(_ report: SightingReport) async throws(SubmissionError) -> SubmissionOutcome
}

/// Why a submission didn't go through.
public enum SubmissionError: Error, Hashable, Sendable {
    /// Refused for good, so retrying won't help. The reason is meant for the user.
    case rejected(String)
    /// Couldn't get through; try again later.
    case unavailable
}
