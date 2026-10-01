import FireWatchAPI
import FireWatchCore
import Foundation
import Vapor

/// Fans event batches out to every connected `/v1/stream` WebSocket.
actor EventHub {
    private var sockets: [UUID: WebSocket] = [:]

    var connectionCount: Int { sockets.count }

    /// Starts sending batches to `socket` until it closes.
    func add(_ socket: WebSocket) {
        let id = UUID()
        sockets[id] = socket
        socket.onClose.whenComplete { _ in
            Task { await self.remove(id) }
        }
    }

    private func remove(_ id: UUID) {
        sockets[id] = nil
    }

    /// Sends `events` as one ``EventBatchDTO``, encoded once for everyone.
    func broadcast(_ events: [FeedEvent]) async {
        guard !events.isEmpty, !sockets.isEmpty,
            let data = try? API.makeEncoder().encode(EventBatchDTO(events))
        else { return }
        let text = String(decoding: data, as: UTF8.self)
        for socket in sockets.values {
            try? await socket.send(text)
        }
    }

    /// Closes every stream, so clients reconnect and fetch a fresh snapshot.
    func closeAll() async {
        let open = Array(sockets.values)
        sockets.removeAll()
        for socket in open {
            try? await socket.close(code: .goingAway)
        }
    }
}

/// One tick: advance the simulation and push whatever happened to every stream.
struct StreamPump: Sendable {
    let simulation: FireSimulation
    let hub: EventHub

    func tick() async {
        await hub.broadcast(await simulation.advance())
    }
}
