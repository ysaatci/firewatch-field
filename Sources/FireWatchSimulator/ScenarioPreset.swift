import FireWatchCore

/// Named, ready-made scenarios.
public enum ScenarioPreset: String, CaseIterable, Sendable {
    /// A four-hour fire in the forested hills north-east of Manavgat, Antalya.
    case manavgat
    /// A larger, hotter fire that leaves over 2,000 hotspots, for performance testing (NFR-2).
    case stress

    public static let `default` = ScenarioPreset.manavgat

    public var configuration: ScenarioConfiguration {
        let manavgatHills = Coordinate(latitude: 36.83, longitude: 31.47)
        switch self {
        case .manavgat:
            return ScenarioConfiguration(seed: 2021, centre: manavgatHills)
        case .stress:
            var configuration = ScenarioConfiguration(
                seed: 2021,
                centre: manavgatHills,
                rows: 160,
                columns: 160,
                minutes: 300,
                wind: Wind(speed: 8, fromDegrees: 250)
            )
            configuration.fire.ignitionRate = 0.075
            configuration.residuals.smoulderChance = 0.9
            configuration.residuals.coolingMinutes = 120...300
            configuration.survey.droneCount = 6
            return configuration
        }
    }
}
