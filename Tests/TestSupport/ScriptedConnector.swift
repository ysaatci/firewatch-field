import FireWatchCore
import Foundation

/// A connector that plays a script: each connection attempt either fails or yields a socket
/// that delivers the given messages and then closes.
public final class ScriptedConnector: SocketConnector, @unchecked Sendable {
    public enum Step: Sendable {
        case fail
        case connect([String])
    }

    private let lock = NSLock()
    private var steps: [Step]

    public init(_ steps: [Step]) {
        self.steps = steps
    }

    public func connect() async throws -> any MessageSocket {
        let step: Step? = lock.withLock { steps.isEmpty ? nil : steps.removeFirst() }
        switch step {
        case .connect(let messages): return ScriptedSocket(messages)
        case .fail: throw ConnectionRefused()
        case nil:
            // Past the script, attempts hang like an unreachable server until cancelled. Failing
            // at once would let a reconnect loop with a no-op sleep spin forever after the test,
            // and on a small thread pool (CI runners) starve every other test.
            try await Task.sleep(for: .seconds(3600))
            throw ConnectionRefused()
        }
    }
}

/// Delivers a fixed list of messages, then reports the connection closed.
public final class ScriptedSocket: MessageSocket, @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String]

    public init(_ messages: [String]) {
        self.messages = messages
    }

    public func receive() async throws -> String? {
        lock.withLock { messages.isEmpty ? nil : messages.removeFirst() }
    }

    public func close() async {}
}

/// The error a scripted connection attempt fails with.
public struct ConnectionRefused: Error {}
