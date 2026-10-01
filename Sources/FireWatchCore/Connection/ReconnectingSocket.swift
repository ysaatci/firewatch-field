import Foundation

/// A connection delivering text messages, such as a WebSocket.
public protocol MessageSocket: Sendable {
    /// The next message, or `nil` once the connection has closed. Throws if it failed.
    func receive() async throws -> String?
    func close() async
}

/// Opens connections. Throws if the connection can't be established.
public protocol SocketConnector: Sendable {
    func connect() async throws -> any MessageSocket
}

/// Keeps a socket connected, reconnecting with ``Backoff`` whenever it drops (NFR-4), and
/// reports its life as a stream of events.
public struct ReconnectingSocket: Sendable {
    public enum Event: Hashable, Sendable {
        case connected
        case message(String)
        /// Lost or couldn't connect; the next attempt is due at `retryAt`.
        case disconnected(retryAt: Date)
    }

    private let connector: any SocketConnector
    private let backoff: Backoff
    private let now: @Sendable () -> Date
    private let random: @Sendable () -> Double
    private let sleep: @Sendable (Duration) async throws -> Void

    public init(
        connector: any SocketConnector,
        backoff: Backoff = Backoff(),
        now: @escaping @Sendable () -> Date = Date.init,
        random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.connector = connector
        self.backoff = backoff
        self.now = now
        self.random = random
        self.sleep = sleep
    }

    /// Connects and keeps reconnecting until the stream is cancelled, which also closes the socket.
    public func events() -> AsyncStream<Event> {
        AsyncStream { continuation in
            let task = Task { await run(continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ continuation: AsyncStream<Event>.Continuation) async {
        var failures = 0
        while !Task.isCancelled {
            if let socket = try? await connector.connect() {
                failures = 0
                continuation.yield(.connected)
                await withTaskCancellationHandler {
                    while let message = try? await socket.receive() {
                        continuation.yield(.message(message))
                    }
                } onCancel: {
                    Task { await socket.close() }
                }
                await socket.close()
            }
            guard !Task.isCancelled else { break }
            let delay = backoff.delay(forAttempt: failures, unit: random())
            failures += 1
            continuation.yield(.disconnected(retryAt: now().addingTimeInterval(delay.seconds)))
            do {
                try await sleep(delay)
            } catch {
                break
            }
        }
        continuation.finish()
    }
}

extension Duration {
    /// The duration in seconds, as a `TimeInterval`.
    public var seconds: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
