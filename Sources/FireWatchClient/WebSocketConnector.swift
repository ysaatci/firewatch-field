import FireWatchCore
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Opens the event stream with `URLSessionWebSocketTask`.
///
/// Apple platforms only in practice: the Linux toolchain's libcurl lacks WebSocket support,
/// so Linux tests inject a different ``SocketConnector``.
public struct WebSocketConnector: SocketConnector {
    /// Batches carrying perimeters can be a few hundred kilobytes.
    public static let maximumMessageSize = 4 * 1_024 * 1_024

    private let url: URL
    private let headers: [String: String]
    private let session: URLSession

    public init(url: URL, headers: [String: String], session: URLSession = .shared) {
        self.url = url
        self.headers = headers
        self.session = session
    }

    public func connect() async throws -> any MessageSocket {
        var request = URLRequest(url: url)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = Self.maximumMessageSize
        task.resume()
        // The task connects lazily; a ping surfaces a failed connection as an error here.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            task.sendPing { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        return WebSocketTaskSocket(task: task)
    }
}

/// A ``MessageSocket`` over a `URLSessionWebSocketTask`.
struct WebSocketTaskSocket: MessageSocket {
    let task: URLSessionWebSocketTask

    func receive() async throws -> String? {
        switch try await task.receive() {
        case .string(let text): return text
        case .data(let data): return String(decoding: data, as: UTF8.self)
        @unknown default: return nil
        }
    }

    func close() async {
        task.cancel(with: .goingAway, reason: nil)
    }
}
