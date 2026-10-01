import Vapor

/// `/v1/stream`: a WebSocket that receives an ``EventBatchDTO`` every tick (FR-S2).
struct StreamController: RouteCollection {
    let hub: EventHub

    func boot(routes: any RoutesBuilder) throws {
        routes.webSocket("stream") { _, socket async in
            await hub.add(socket)
        }
    }
}
