import FireWatchAPI
import FireWatchCore
import Foundation

/// The simulator server, or later the real backend, as a ``DetectionFeed``: the event stream
/// over WebSocket, with a snapshot over HTTP after every (re)connect.
///
/// The socket opens first and the snapshot is fetched while its messages wait in the stream's
/// buffer, so nothing is missed. Buffered events older than the snapshot are dropped, and the
/// reducer ignores any repeats that remain.
public struct ServerFeed: DetectionFeed {
    private let client: APIClient
    private let socket: ReconnectingSocket
    private let now: @Sendable () -> Date
    /// How long to wait before the next snapshot attempt after one fails.
    private let snapshotRetry: TimeInterval

    public init(
        client: APIClient,
        socket: ReconnectingSocket? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        snapshotRetry: TimeInterval = 5
    ) {
        self.client = client
        self.socket =
            socket
            ?? ReconnectingSocket(
                connector: WebSocketConnector(url: client.streamURL, headers: client.authorizationHeaders))
        self.now = now
        self.snapshotRetry = snapshotRetry
    }

    public func updates() -> AsyncStream<FeedUpdate> {
        AsyncStream { continuation in
            let task = Task { await run(continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ continuation: AsyncStream<FeedUpdate>.Continuation) async {
        continuation.yield(.connection(.connecting))
        /// The snapshot's time, once this connection has one.
        var snapshotTime: Date?
        for await event in socket.events() {
            switch event {
            case .connected:
                snapshotTime = await fetchSnapshot(into: continuation)
            case .message(let text):
                if snapshotTime == nil { snapshotTime = await fetchSnapshot(into: continuation) }
                guard let since = snapshotTime else { continue }
                let events = Self.decode(text).filter { $0.time >= since }
                if !events.isEmpty { continuation.yield(.events(events)) }
            case .disconnected(let retryAt):
                snapshotTime = nil
                continuation.yield(.connection(.offline(retryAt: retryAt)))
            }
        }
        continuation.finish()
    }

    /// Fetches and yields a snapshot, returning its time, or reports the feed offline.
    private func fetchSnapshot(into continuation: AsyncStream<FeedUpdate>.Continuation) async -> Date? {
        do {
            let (state, asOf) = try await client.snapshot()
            continuation.yield(.snapshot(state, asOf: asOf))
            continuation.yield(.connection(.live))
            return asOf
        } catch {
            continuation.yield(.connection(.offline(retryAt: now().addingTimeInterval(snapshotRetry))))
            return nil
        }
    }

    /// The events in one stream message; malformed messages are skipped.
    static func decode(_ text: String) -> [FeedEvent] {
        guard let batch = try? API.makeDecoder().decode(EventBatchDTO.self, from: Data(text.utf8)),
            let events = try? batch.feedEvents()
        else { return [] }
        return events
    }
}

/// Sends crew commands and reports to the server.
public struct ServerCommandSink: CommandSink {
    private let client: APIClient
    /// Loads a report's photo by its file name; reports without one are sent without a photo.
    private let loadPhoto: @Sendable (String) -> Data?

    public init(client: APIClient, loadPhoto: @escaping @Sendable (String) -> Data? = { _ in nil }) {
        self.client = client
        self.loadPhoto = loadPhoto
    }

    public func submit(_ command: HotspotCommand) async throws(SubmissionError) -> SubmissionOutcome {
        do {
            return try await client.submit(command)
        } catch {
            throw Self.submissionError(error)
        }
    }

    public func submit(_ report: SightingReport) async throws(SubmissionError) -> SubmissionOutcome {
        do {
            return try await client.submit(report, photoJPEG: report.photoFileName.flatMap(loadPhoto))
        } catch {
            throw Self.submissionError(error)
        }
    }

    static func submissionError(_ error: APIError) -> SubmissionError {
        error.isTransient ? .unavailable : .rejected(error.message)
    }
}
