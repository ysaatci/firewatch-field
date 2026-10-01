import FireWatchAPI
import FireWatchClient
import FireWatchCore
import Foundation
import NIOConcurrencyHelpers
import Testing
import VaporTesting

@testable import FireWatchServer

/// The app's networking stack (`ServerFeed`, `APIClient` over `URLSession`, the command sink)
/// against the real server.
///
/// The WebSocket comes from WebSocketKit rather than `URLSessionWebSocketTask`: the Linux
/// toolchain's libcurl is built without WebSocket support. The URLSession adapter runs on iOS.
struct EndToEndTests {
    @Test func feedAndSinkWorkAgainstTheServer() async throws {
        try await withTestApp { app, clock in
            try await app.server.start(address: .hostname("127.0.0.1", port: 0))
            do {
                try await exercise(app, clock)
            } catch {
                await app.server.shutdown()
                throw error
            }
            await app.server.shutdown()
        }
    }

    private func exercise(_ app: Application, _ clock: TestClock) async throws {
        let port = try #require(app.http.server.shared.localAddress?.port)
        let baseURL = try #require(URL(string: "http://127.0.0.1:\(port)"))
        let client = APIClient(configuration: .init(baseURL: baseURL, token: testToken))
        let services = try #require(app.simulator)
        let connector = WebSocketKitConnector(
            url: client.streamURL.absoluteString, headers: client.authorizationHeaders,
            eventLoopGroup: app.eventLoopGroup)
        let feed = ServerFeed(client: client, socket: ReconnectingSocket(connector: connector))

        var updates = feed.updates().makeAsyncIterator()
        #expect(await updates.next() == .connection(.connecting))
        guard case .snapshot(let state, _)? = await updates.next() else {
            Issue.record("expected a snapshot")
            return
        }
        #expect(await updates.next() == .connection(.live))
        let serverState = await services.simulation.state  // snapshots carry only the latest perimeter
        #expect(state.hotspots == serverState.hotspots)
        #expect(state.drones == serverState.drones)
        try await waitUntil { await services.hub.connectionCount == 1 }

        clock.advance(seconds: 30)
        await services.pump.tick()
        guard case .events(let ticked)? = await updates.next() else {
            Issue.record("expected the tick's events")
            return
        }
        #expect(!ticked.isEmpty)

        let hotspot = try #require(state.hotspots.keys.min())
        let command = HotspotCommand(hotspotID: hotspot, action: .assign, issuedAt: .now)
        #expect(try await ServerCommandSink(client: client).submit(command) == .applied)
        guard case .events(let applied)? = await updates.next(), case .hotspotCommandApplied(let echoed) = applied.first
        else {
            Issue.record("expected the command to come back on the stream")
            return
        }
        #expect(echoed.id == command.id)
    }
}

/// A ``SocketConnector`` on WebSocketKit, for tests on Linux.
struct WebSocketKitConnector: SocketConnector {
    let url: String
    let headers: [String: String]
    let eventLoopGroup: any EventLoopGroup

    func connect() async throws -> any MessageSocket {
        let (messages, continuation) = AsyncStream.makeStream(of: String.self)
        let socket = NIOLockedValueBox<WebSocket?>(nil)
        try await WebSocket.connect(
            to: url, headers: HTTPHeaders(headers.map { ($0, $1) }),
            configuration: .init(maxFrameSize: 1 << 22), on: eventLoopGroup
        ) { ws in
            socket.withLockedValue { $0 = ws }
            ws.onText { _, text in continuation.yield(text) }
            ws.onClose.whenComplete { _ in continuation.finish() }
        }.get()
        try await waitUntil { socket.withLockedValue { $0 != nil } }
        return KitSocket(socket: try #require(socket.withLockedValue { $0 }), messages: messages)
    }

    final class KitSocket: MessageSocket, @unchecked Sendable {
        let socket: WebSocket
        var iterator: AsyncStream<String>.Iterator

        init(socket: WebSocket, messages: AsyncStream<String>) {
            self.socket = socket
            self.iterator = messages.makeAsyncIterator()
        }

        func receive() async throws -> String? { await iterator.next() }
        func close() async { try? await socket.close() }
    }
}
