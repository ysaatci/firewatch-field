import FireWatchCore
import Foundation

/// A scenario playing out from a start date, including what crews do to it.
///
/// The scenario fixes where the fire goes and when drones fly over each hotspot. Crews
/// change what those drones measure: once a hotspot is extinguished it reads cool, unless
/// it has a flare-up scheduled after that, which reheats it on schedule.
public struct SimulatedWorld: Sendable {
    public let scenario: Scenario
    public let start: Date
    private let timeline: [Entry]
    /// The latest minute a crew put each hotspot out.
    private var extinguishedAt: [Hotspot.ID: Double] = [:]

    private struct Entry: Sendable {
        enum Kind: Int, Sendable {
            case drone, observation, perimeter
        }
        var minute: Double
        var kind: Kind
        /// Index into the routes, passes or perimeters, by kind.
        var index: Int
    }

    public init(scenario: Scenario, start: Date) {
        self.scenario = scenario
        self.start = start
        let survey = scenario.configuration.survey
        let droneEntries = survey.sampleTimes(minutes: scenario.configuration.minutes).flatMap { second in
            scenario.routes.indices.map { Entry(minute: second / 60, kind: .drone, index: $0) }
        }
        let passEntries = scenario.passes.enumerated().map { Entry(minute: $1.minute, kind: .observation, index: $0) }
        let perimeterEntries = scenario.perimeters.enumerated().map {
            Entry(minute: Double($1.minute), kind: .perimeter, index: $0)
        }
        timeline = (droneEntries + passEntries + perimeterEntries).sorted {
            ($0.minute, $0.kind.rawValue, $0.index) < ($1.minute, $1.kind.rawValue, $1.index)
        }
    }

    public var end: Date { date(atMinute: Double(scenario.configuration.minutes)) }

    public func minute(at date: Date) -> Double {
        date.timeIntervalSince(start) / 60
    }

    public func date(atMinute minute: Double) -> Date {
        // Whole milliseconds, so times survive the ISO 8601 wire format exactly.
        start.addingTimeInterval((minute * 60_000).rounded() / 1_000)
    }

    /// Records a crew command; only `extinguish` changes what drones measure.
    public mutating func intervene(_ command: HotspotCommand) {
        guard command.action == .extinguish else { return }
        extinguishedAt[command.hotspotID] = minute(at: command.issuedAt)
    }

    /// Events with times in `from..<to`, in time order.
    public func events(from: Date, to: Date) -> [FeedEvent] {
        let lower = minute(at: from)
        let upper = minute(at: to)
        let first = timeline.partitioningIndex { $0.minute >= lower }
        return timeline[first...].prefix { $0.minute < upper }.map(event)
    }

    /// What a drone would measure at `minute`, or `nil` before the hotspot appears.
    public func celsius(of hotspot: ResidualHotspot, atMinute minute: Double) -> Double? {
        let ambient = scenario.configuration.ambientCelsius
        guard let undisturbed = hotspot.celsius(atMinute: minute, ambient: ambient) else { return nil }
        guard let putOut = extinguishedAt[hotspot.id], minute >= putOut else { return undisturbed }
        if let flareUp = hotspot.flareUp, flareUp.startMinute > putOut, minute >= flareUp.startMinute {
            return flareUp.celsius(atMinute: minute, ambient: ambient)
        }
        return ambient + 5 * exp(-(minute - putOut) / 30)  // damp ash settling to ambient
    }

    private func event(for entry: Entry) -> FeedEvent {
        switch entry.kind {
        case .drone: droneEvent(route: scenario.routes[entry.index], minute: entry.minute)
        case .observation: observationEvent(scenario.passes[entry.index])
        case .perimeter: perimeterEvent(scenario.perimeters[entry.index])
        }
    }

    private func droneEvent(route: SurveyRoute, minute: Double) -> FeedEvent {
        let second = minute * 60
        let location = route.location(atSecond: second)
        let position = DronePosition(
            time: date(atMinute: minute),
            coordinate: scenario.terrain.projection.unproject(location.point),
            headingDegrees: location.headingDegrees,
            altitudeMetres: route.altitudeMetres,
            battery: route.battery(atSecond: second)
        )
        return .droneMoved(DroneUpdate(droneID: route.droneID, name: route.name, position: position))
    }

    private func observationEvent(_ pass: DronePass) -> FeedEvent {
        let hotspot = scenario.hotspots[pass.hotspot]
        let celsius = celsius(of: hotspot, atMinute: pass.minute) ?? scenario.configuration.ambientCelsius
        let confidence = scenario.configuration.survey.confidence(celsius: celsius, distance: pass.distance)
        return .hotspotObserved(
            HotspotObservation(
                hotspotID: hotspot.id,
                coordinate: hotspot.coordinate,
                reading: TemperatureReading(time: date(atMinute: pass.minute), celsius: (celsius * 10).rounded() / 10),
                confidence: (confidence * 100).rounded() / 100,
                droneID: pass.droneID
            ))
    }

    private func perimeterEvent(_ perimeter: ScenarioPerimeter) -> FeedEvent {
        .perimeterUpdated(FirePerimeter(time: date(atMinute: Double(perimeter.minute)), polygons: perimeter.polygons))
    }
}

extension RandomAccessCollection {
    /// The first index where `predicate` is true, assuming it is false then true across the collection.
    func partitioningIndex(where predicate: (Element) -> Bool) -> Index {
        var low = startIndex
        var count = distance(from: startIndex, to: endIndex)
        while count > 0 {
            let half = count / 2
            let middle = index(low, offsetBy: half)
            if predicate(self[middle]) {
                count = half
            } else {
                low = index(after: middle)
                count -= half + 1
            }
        }
        return low
    }
}
