import Foundation

/// Everything known about the fire, built by applying ``FeedEvent``s in order.
///
/// The server and the app both use this reducer, so they can't disagree about what an
/// event means.
public struct FireState: Hashable, Sendable {
    /// A reading at or above this on an extinguished or verified-cold hotspot means it flared up.
    public static let flareUpCelsius = 150.0

    public private(set) var hotspots: [Hotspot.ID: Hotspot] = [:]
    public private(set) var drones: [Drone.ID: Drone] = [:]
    /// Perimeters in time order.
    public private(set) var perimeters: [FirePerimeter] = []

    public init() {}

    public init(events: some Sequence<FeedEvent>) {
        for event in events { apply(event) }
    }

    /// Restores a stored state, such as a server snapshot.
    public init(hotspots: some Sequence<Hotspot>, drones: some Sequence<Drone>, perimeters: [FirePerimeter]) {
        self.hotspots = Dictionary(hotspots.map { ($0.id, $0) }) { _, latest in latest }
        self.drones = Dictionary(drones.map { ($0.id, $0) }) { _, latest in latest }
        self.perimeters = perimeters.sorted { $0.time < $1.time }
    }

    public var latestPerimeter: FirePerimeter? { perimeters.last }

    /// Applies one event. Commands that are no longer legal are ignored; use ``execute(_:)``
    /// to validate a new command.
    public mutating func apply(_ event: FeedEvent) {
        switch event {
        case .hotspotObserved(let observation):
            observe(observation)
        case .hotspotCommandApplied(let command):
            _ = try? execute(command)
        case .perimeterUpdated(let perimeter):
            guard perimeter.time > latestPerimeter?.time ?? .distantPast else { return }
            perimeters.append(perimeter)
        case .droneMoved(let update):
            if drones[update.droneID] == nil {
                drones[update.droneID] = Drone(id: update.droneID, name: update.name, position: update.position)
            } else {
                drones[update.droneID]?.move(to: update.position)
            }
        }
    }

    /// Applies a crew command if the hotspot's workflow allows it.
    /// - Returns: The event recording the command, for broadcasting to others.
    /// - Throws: ``CommandRejection`` when the hotspot is unknown or the action isn't allowed.
    @discardableResult
    public mutating func execute(_ command: HotspotCommand) throws(CommandRejection) -> FeedEvent {
        guard let hotspot = hotspots[command.hotspotID] else { throw .unknownHotspot(command.hotspotID) }
        do {
            hotspots[command.hotspotID]?.workflow = try hotspot.workflow.applying(command.action)
        } catch {
            throw .notAllowed(error)
        }
        return .hotspotCommandApplied(command)
    }

    private mutating func observe(_ observation: HotspotObservation) {
        guard var hotspot = hotspots[observation.hotspotID] else {
            hotspots[observation.hotspotID] = Hotspot(
                id: observation.hotspotID,
                coordinate: observation.coordinate,
                confidence: observation.confidence,
                reading: observation.reading
            )
            return
        }
        // Old or repeated readings change nothing, so replaying events is harmless.
        guard hotspot.record(observation.reading, confidence: observation.confidence) else { return }
        let putOut = [HotspotStatus.extinguished, .verifiedCold].contains(hotspot.status)
        if putOut, observation.reading.celsius >= Self.flareUpCelsius {
            hotspot.workflow = (try? hotspot.workflow.applying(.flareUp)) ?? hotspot.workflow
        }
        hotspots[observation.hotspotID] = hotspot
    }
}

/// Why a crew command was refused.
public enum CommandRejection: Error, Hashable, Sendable {
    case unknownHotspot(Hotspot.ID)
    case notAllowed(WorkflowError)
}

extension CommandRejection: CustomStringConvertible {
    /// A sentence for logs, error bodies and the user.
    public var description: String {
        switch self {
        case .unknownHotspot(let id): "No hotspot \(id) has been detected"
        case .notAllowed(let error): "\(error.action.rawValue) is not allowed from \(error.status.rawValue)"
        }
    }
}
