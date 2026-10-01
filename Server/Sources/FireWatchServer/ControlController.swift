import FireWatchAPI
import Vapor

/// `/v1/control`: drives the replay (FR-S3).
struct ControlController: RouteCollection {
    let simulation: FireSimulation

    func boot(routes: any RoutesBuilder) throws {
        let control = routes.grouped("control")
        control.get { _ in try Response.json(await simulation.status()) }
        control.post { request in
            let command = try request.decodeBody(ReplayControlDTO.self)
            return try Response.json(try await simulation.control(command).status)
        }
    }
}
