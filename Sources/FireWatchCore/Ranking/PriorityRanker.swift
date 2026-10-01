import Foundation

/// Orders hotspots by how urgently a crew should deal with them.
///
/// The score is a weighted sum of three factors, each in `0...1`:
/// - **heat**: temperature above ambient, saturating at ``heatSaturationCelsius``;
/// - **recency**: halves every ``recencyHalfLife`` since the last reading;
/// - **proximity**: halves every ``proximityHalfDistance`` metres from the user, or 0 when
///   the user's location is unknown (it is then the same for every hotspot).
///
/// The sum is scaled by how much work the status still needs, so hotspots someone is
/// already handling sink, and verified-cold ones go to the bottom.
public struct PriorityRanker: Sendable {
    public var heatWeight = 0.5
    public var recencyWeight = 0.3
    public var proximityWeight = 0.2
    public var ambientCelsius = 30.0
    public var heatSaturationCelsius = 400.0
    public var recencyHalfLife: TimeInterval = 30 * 60
    public var proximityHalfDistance = 2_000.0

    public init() {}

    public func score(of hotspot: Hotspot, now: Date, userLocation: Coordinate?) -> Double {
        let heat = min(max(hotspot.temperatureCelsius - ambientCelsius, 0) / heatSaturationCelsius, 1)
        let recency = Self.halving(max(now.timeIntervalSince(hotspot.lastSeen), 0), every: recencyHalfLife)
        let proximity =
            userLocation.map {
                Self.halving($0.distance(to: hotspot.coordinate), every: proximityHalfDistance)
            } ?? 0
        let urgency = heatWeight * heat + recencyWeight * recency + proximityWeight * proximity
        return urgency * Self.remainingWork(hotspot.status)
    }

    /// `hotspots` from most to least urgent. Ties are broken by ID so the order is stable.
    public func ranked(_ hotspots: some Sequence<Hotspot>, now: Date, userLocation: Coordinate?) -> [Hotspot]
    {
        hotspots
            .map { (hotspot: $0, score: score(of: $0, now: now, userLocation: userLocation)) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.hotspot.id < $1.hotspot.id }
            .map(\.hotspot)
    }

    private static func halving(_ value: Double, every halfLife: Double) -> Double {
        exp2(-value / halfLife)
    }

    private static func remainingWork(_ status: HotspotStatus) -> Double {
        switch status {
        case .new, .flaredUp: 1
        case .assigned: 0.8
        case .extinguished: 0.3
        case .verifiedCold: 0
        }
    }
}
