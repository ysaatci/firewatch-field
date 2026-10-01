import FireWatchCore
import SwiftUI

/// Hotspots, most urgent first (FR-4).
struct HotspotListScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(LocationProvider.self) private var location
    @State private var filter = HotspotFilter.open

    var body: some View {
        let hotspots = ranked
        List(hotspots) { hotspot in
            NavigationLink(value: hotspot.id) {
                HotspotRow(hotspot: hotspot, asOf: model.field.asOf, user: location.coordinate)
            }
            .accessibilityIdentifier("row.\(hotspot.id)")
        }
        .overlay {
            if hotspots.isEmpty {
                ContentUnavailableView(
                    "No hotspots", systemImage: "flame",
                    description: Text("Nothing matches the filter yet. Drones report new hotspots as they find them."))
            }
        }
        .navigationTitle("Hotspots")
        .navigationDestination(for: Hotspot.ID.self) { HotspotDetailScreen(hotspotID: $0) }
        .toolbar { filterMenu }
    }

    private var ranked: [Hotspot] {
        PriorityRanker().ranked(
            model.field.fire.hotspots.values.filter(filter.includes),
            now: model.field.asOf ?? .now,
            userLocation: location.coordinate
        )
    }

    private var filterMenu: some View {
        Menu {
            Picker("Minimum severity", selection: $filter.minimumSeverity) {
                ForEach(Severity.allCases, id: \.self) { severity in
                    Label(resource: severity.label, systemImage: severity.symbol).tag(severity)
                }
            }
            Toggle(
                "Show verified cold",
                isOn: Binding(
                    get: { filter.statuses.contains(.verifiedCold) },
                    set: { show in
                        if show { filter.statuses.insert(.verifiedCold) } else { filter.statuses.remove(.verifiedCold) }
                    }
                ))
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
        }
        .accessibilityIdentifier("filter")
    }
}

/// One line of the list: what, how hot, where, and how recently seen.
struct HotspotRow: View {
    let hotspot: Hotspot
    let asOf: Date?
    let user: Coordinate?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: hotspot.severity.symbol)
                .foregroundStyle(hotspot.severity.color)
                .font(.title2)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int(hotspot.temperatureCelsius)) °C")
                    .font(.headline.monospacedDigit())
                Text(details)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label(resource: hotspot.status.label, systemImage: hotspot.status.symbol)
                .labelStyle(.iconOnly)
                .foregroundStyle(.blue)
        }
        .accessibilityElement(children: .combine)
    }

    private var details: String {
        var parts: [String] = []
        if let user { parts.append(Direction(from: user, to: hotspot.coordinate).text) }
        if let asOf { parts.append(String(localized: "seen \(RelativeTime(from: hotspot.lastSeen, to: asOf).text)")) }
        return parts.joined(separator: " · ")
    }
}

/// "1.2 km NE" from one point to another.
struct Direction {
    let from: Coordinate
    let to: Coordinate

    var text: String {
        let metres = from.distance(to: to)
        let distance = Measurement(value: metres, unit: UnitLength.meters)
            .formatted(
                .measurement(
                    width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0...1))))
        return "\(distance) \(CompassPoint(degrees: from.bearing(to: to)).rawValue)"
    }
}
