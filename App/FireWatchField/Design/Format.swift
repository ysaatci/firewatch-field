import Foundation

/// Which measurement system to show (FR-10).
enum UnitSystem: String, CaseIterable, Identifiable {
    case automatic, metric, imperial

    var id: Self { self }

    static let defaultsKey = "units"

    static var current: UnitSystem {
        UnitSystem(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .automatic
    }

    var label: LocalizedStringResource {
        switch self {
        case .automatic: "Automatic"
        case .metric: "Metric (°C, km)"
        case .imperial: "Imperial (°F, mi)"
        }
    }

    /// The locale formatting follows: the user's own, with the measurement system overridden if chosen.
    var locale: Locale {
        var components = Locale.Components(locale: .current)
        switch self {
        case .automatic: return .current
        case .metric: components.measurementSystem = .metric
        case .imperial: components.measurementSystem = .us
        }
        return Locale(components: components)
    }
}

/// Temperatures and distances in the user's units, everywhere in the app.
enum Format {
    static func temperature(_ celsius: Double) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius)
            .formatted(
                .measurement(
                    width: .abbreviated, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))
                )
                .locale(UnitSystem.current.locale))
    }

    static func distance(_ metres: Double) -> String {
        Measurement(value: metres, unit: UnitLength.meters)
            .formatted(
                .measurement(
                    width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0...1))
                )
                .locale(UnitSystem.current.locale))
    }
}
