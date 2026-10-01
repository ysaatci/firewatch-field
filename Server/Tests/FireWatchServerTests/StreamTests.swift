import FireWatchAPI
import Foundation
import NIOConcurrencyHelpers
import Testing
import VaporTesting

@testable import FireWatchServer

/// End-to-end: a real server on a random port and a real WebSocket client.
struct StreamTests {
    /// A connected client: its text messages, and a signal when the server closes it.
    struct Client {
        let socket: WebSocket
        let messages: AsyncStream<String>
    }

    func connect(_ app: Application) async throws -> Client {
        let port = try #require(app.http.server.shared.localAddress?.port)
        let (messages, continuation) = AsyncStream.makeStream(of: String.self)
        let socket = NIOLockedValueBox<WebSocket?>(nil)
        // Batches with perimeters exceed the 16 KB default frame limit.
        let configuration = WebSocketClient.Configuration(maxFrameSize: 1 << 22)
        try await WebSocket.connect(
            to: "ws://127.0.0.1:\(port)/v1/stream", configuration: configuration, on: app.eventLoopGroup
        ) { ws in
            socket.withLockedValue { $0 = ws }
            ws.onText { _, text in continuation.yield(text) }
            ws.onClose.whenComplete { _ in continuation.finish() }
        }.get()
        let services = try #require(app.simulator)
        try await waitUntil { await services.hub.connectionCount == 1 }
        return Client(socket: try #require(socket.withLockedValue { $0 }), messages: messages)
    }

    func withRunningApp(_ test: (Application, TestClock) async throws -> Void) async throws {
        try await withTestApp { app, clock in
            try await app.server.start(address: .hostname("127.0.0.1", port: 0))
            do {
                try await test(app, clock)
            } catch {
                await app.server.shutdown()
                throw error
            }
            await app.server.shutdown()
        }
    }

    @Test func eachTickArrivesAsOneBatch() async throws {
        try await withRunningApp { app, clock in
            let client = try await connect(app)
            let services = try #require(app.simulator)

            clock.advance(seconds: 30)
            await services.pump.tick()

            var iterator = client.messages.makeAsyncIterator()
            let text = try #require(await iterator.next())
            let batch = try API.makeDecoder().decode(EventBatchDTO.self, from: Data(text.utf8))
            let events = try batch.feedEvents()
            #expect(!events.isEmpty)
            #expect(events.map(\.time) == events.map(\.time).sorted())
            #expect(await services.simulation.state.drones.count == 3)
            try await client.socket.close()
        }
    }

    @Test func resetClosesStreams() async throws {
        try await withRunningApp { app, _ in
            let client = try await connect(app)
            _ = try await app.testing().sendRequest(.POST, "v1/control") {
                try $0.encode(ReplayControlDTO(action: .reset))
            }
            var iterator = client.messages.makeAsyncIterator()
            #expect(await iterator.next() == nil)  // the stream ended
            let services = try #require(app.simulator)
            #expect(await services.hub.connectionCount == 0)
        }
    }

    @Test func quietTicksSendNothing() async throws {
        try await withRunningApp { app, _ in
            let client = try await connect(app)
            let services = try #require(app.simulator)
            await services.pump.tick()  // the clock hasn't moved
            try await client.socket.close()
            var iterator = client.messages.makeAsyncIterator()
            #expect(await iterator.next() == nil)
        }
    }
}

/// Polls `condition` until it holds, failing after `timeout`.
func waitUntil(timeout: Duration = .seconds(5), _ condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !(await condition()) {
        guard ContinuousClock.now < deadline else {
            Issue.record("Timed out waiting for condition")
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}
