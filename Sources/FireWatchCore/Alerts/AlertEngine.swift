/// Something near the crew worth interrupting them for (FR-8).
public struct HotspotAlert: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable {
        case newHotspot, flareUp
    }

    public var kind: Kind
    public var hotspotID: Hotspot.ID
    public var severity: Severity
    public var distanceMetres: Double
    /// Which flare-up this is, so a hotspot that flares up twice alerts twice.
    public var flareUps: Int

    /// Stable across recomputation, so the same alert is never shown twice.
    public var id: String { "\(kind.rawValue)/\(hotspotID)/\(flareUps)" }
}

/// Decides which changes deserve an alert: new hotspots and flare-ups within a radius of the user.
public struct AlertEngine: Sendable {
    public var radiusMetres: Double

    public init(radiusMetres: Double = 2_000) {
        self.radiusMetres = radiusMetres
    }

    /// Alerts for what changed from `old` to `new`, nearest first.
    ///
    /// Without a user location nothing counts as near, so there are no alerts. The first
    /// state after launch (an empty `old`) raises none either; otherwise every existing
    /// hotspot would alert at once. Hotspots found while offline do alert after a reconnect.
    public func alerts(from old: FireState, to new: FireState, near user: Coordinate?) -> [HotspotAlert] {
        guard let user, !old.hotspots.isEmpty else { return [] }
        return new.hotspots.values
            .compactMap { hotspot -> HotspotAlert? in
                let distance = user.distance(to: hotspot.coordinate)
                guard distance <= radiusMetres, let kind = change(of: hotspot, since: old) else { return nil }
                return HotspotAlert(
                    kind: kind, hotspotID: hotspot.id, severity: hotspot.severity, distanceMetres: distance,
                    flareUps: hotspot.workflow.flareUps)
            }
            .sorted { ($0.distanceMetres, $0.id) < ($1.distanceMetres, $1.id) }
    }

    private func change(of hotspot: Hotspot, since old: FireState) -> HotspotAlert.Kind? {
        guard let before = old.hotspots[hotspot.id] else { return .newHotspot }
        return hotspot.workflow.flareUps > before.workflow.flareUps ? .flareUp : nil
    }
}
