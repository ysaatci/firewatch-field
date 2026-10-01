import FireWatchAPI
import Vapor

/// `/v1/control`: drives the replay (FR-S3) and injects faults (FR-S5).
struct ControlController: RouteCollection {
    let simulation: FireSimulation
    let hub: EventHub
    let faults: FaultInjector

    func boot(routes: any RoutesBuilder) throws {
        let control = routes.grouped("control")
        control.get { _ in try Response.json(await simulation.status()) }
        control.post { request in
            let command = try request.decodeBody(ReplayControlDTO.self)
            let (status, restarted) = try await simulation.control(command)
            if restarted { await hub.closeAll() }
            return try Response.json(status)
        }
        control.get("faults") { _ in try Response.json(await faults.settings) }
        control.post("faults") { request in
            try Response.json(try await faults.update(request.decodeBody(FaultsDTO.self)))
        }
        control.post("disconnect") { _ in
            await hub.closeAll()
            return Response(status: .noContent)
        }
    }
}
