import Foundation

/// A feed frozen at one state, for previews and snapshot tests. Accepts every submission
/// without changing anything.
public struct FixtureFeed: DetectionFeed, CommandSink {
    public let state: FireState
    public let asOf: Date

    public init(state: FireState, asOf: Date) {
        self.state = state
        self.asOf = asOf
    }

    public func updates() -> AsyncStream<FeedUpdate> {
        AsyncStream { continuation in
            continuation.yield(.connection(.live))
            continuation.yield(.snapshot(state, asOf: asOf))
        }
    }

    public func submit(_ command: HotspotCommand) async throws(SubmissionError) -> SubmissionOutcome { .applied }
    public func submit(_ report: SightingReport) async throws(SubmissionError) -> SubmissionOutcome { .applied }
}
