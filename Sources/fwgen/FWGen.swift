import ArgumentParser
import FireWatchAPI
import FireWatchCore
import FireWatchSimulator
import Foundation

@main
struct FWGen: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fwgen",
        abstract: "Export a simulated wildfire scenario as FireWatch API JSON.",
        discussion: """
            Writes snapshot.json (the API snapshot at --minutes), perimeters.geojson (perimeter \
            history, openable in geojson.io or QGIS) and events-sample.json (two events of each type).
            """
    )

    @Option(help: "Scenario preset.")
    var preset: ScenarioPreset = .default

    @Option(help: "Minutes into the scenario to take the snapshot at.")
    var minutes: Int = 180

    @Option(help: "Scenario start time (ISO 8601). Fixed by default so output is reproducible.")
    var start: String = "2026-08-01T10:00:00Z"

    @Option(help: "Output directory; created if missing.")
    var out: String = "fixtures"

    mutating func validate() throws {
        guard minutes >= 0 else { throw ValidationError("--minutes must not be negative.") }
        guard (try? Date.ISO8601FormatStyle().parse(start)) != nil else {
            throw ValidationError("--start must be an ISO 8601 date, for example 2026-08-01T10:00:00Z.")
        }
    }

    func run() throws {
        let startDate = try Date.ISO8601FormatStyle().parse(start)
        let world = SimulatedWorld(scenario: Scenario(preset.configuration), start: startDate)
        let snapshotTime = world.date(atMinute: Double(minutes))
        let events = world.events(from: world.start, to: snapshotTime)
        let state = FireState(events: events)

        let directory = URL(fileURLWithPath: out, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = API.makeEncoder()
        encoder.outputFormatting.insert(.prettyPrinted)

        try encoder.encode(SnapshotDTO(state, generatedAt: snapshotTime))
            .write(to: directory.appendingPathComponent("snapshot.json"))
        try encoder.encode(PerimeterHistoryDTO(features: state.perimeters.map(PerimeterDTO.init)))
            .write(to: directory.appendingPathComponent("perimeters.geojson"))
        try encoder.encode(EventBatchDTO(Self.sample(of: events)))
            .write(to: directory.appendingPathComponent("events-sample.json"))

        let area = (state.latestPerimeter?.areaSquareMetres ?? 0) / 10_000
        print(
            """
            \(preset.rawValue) at minute \(minutes): \(state.hotspots.count) hotspots, \
            \(state.drones.count) drones, \(String(format: "%.0f", area)) ha burned → \(directory.path)
            """)
    }

    /// The first two events of each type, in time order.
    static func sample(of events: [FeedEvent]) -> [FeedEvent] {
        var counts: [String: Int] = [:]
        return events.filter { event in
            let type = EventDTO(event).type
            counts[type, default: 0] += 1
            return counts[type, default: 0] <= 2
        }
    }
}

extension ScenarioPreset: ExpressibleByArgument {}
