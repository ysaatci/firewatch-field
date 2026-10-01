import FireWatchAPI
import FireWatchCore
import Vapor

/// Writes from crews: workflow commands and sighting reports, both idempotent (FR-S4).
struct CrewController: RouteCollection {
    /// Large enough for a phone photo, base64-encoded.
    static let maxReportSize: ByteCount = "10mb"

    let simulation: FireSimulation
    let hub: EventHub

    func boot(routes: any RoutesBuilder) throws {
        routes.post("commands") { request in
            let command = try Self.map { try HotspotCommand(request.decodeBody(CommandDTO.self)) }
            let result: (outcome: SubmissionOutcome, event: FeedEvent?)
            do throws(CommandRejection) {
                result = try await simulation.execute(command)
            } catch {
                throw Self.failure(for: error)
            }
            if let event = result.event { await hub.broadcast([event]) }
            return try Response.json(ReceiptDTO(id: command.id.rawValue, outcome: .init(result.outcome)))
        }
        routes.on(.POST, "reports", body: .collect(maxSize: Self.maxReportSize)) { request in
            let report = try Self.map { try SightingReport(request.decodeBody(ReportDTO.self)) }
            let outcome = await simulation.submit(report)
            return try Response.json(ReceiptDTO(id: report.id.rawValue, outcome: .init(outcome)))
        }
    }

    /// Turns a payload that decodes but holds invalid values into a 400.
    private static func map<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as MappingError {
            throw APIFailure.invalidPayload("\(error)")
        }
    }

    private static func failure(for rejection: CommandRejection) -> APIFailure {
        switch rejection {
        case .unknownHotspot:
            APIFailure(status: .notFound, code: "unknownHotspot", message: rejection.description)
        case .notAllowed:
            APIFailure(status: .conflict, code: "notAllowed", message: rejection.description)
        }
    }
}
