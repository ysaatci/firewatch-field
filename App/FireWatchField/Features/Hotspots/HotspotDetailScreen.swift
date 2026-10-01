import Charts
import FireWatchCore
import MapKit
import SwiftUI

/// Everything about one hotspot, and the workflow actions allowed from its status (FR-5, FR-6).
struct HotspotDetailScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(LocationProvider.self) private var location
    let hotspotID: Hotspot.ID

    var body: some View {
        if let hotspot = model.field.fire.hotspots[hotspotID] {
            List {
                summary(hotspot)
                trend(hotspot)
                whereabouts(hotspot)
                actions(hotspot)
            }
            .navigationTitle("Hotspot")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Hotspot no longer known", systemImage: "questionmark.circle")
        }
    }

    private func summary(_ hotspot: Hotspot) -> some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                Text(Format.temperature(hotspot.temperatureCelsius))
                    .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                    .accessibilityIdentifier("temperature")
                Spacer()
                VStack(alignment: .trailing) {
                    Label(resource: hotspot.severity.label, systemImage: hotspot.severity.symbol)
                        .foregroundStyle(hotspot.severity.color)
                    Label(resource: hotspot.status.label, systemImage: hotspot.status.symbol)
                        .accessibilityIdentifier("status")
                }
                .font(.subheadline.bold())
            }
            LabeledContent("Confidence", value: hotspot.confidence.formatted(.percent.precision(.fractionLength(0))))
            if let asOf = model.field.asOf {
                LabeledContent("First seen", value: RelativeTime(from: hotspot.firstSeen, to: asOf).text)
                LabeledContent("Last measured", value: RelativeTime(from: hotspot.lastSeen, to: asOf).text)
            }
            if hotspot.workflow.flareUps > 0 {
                LabeledContent("Flare-ups", value: "\(hotspot.workflow.flareUps)")
            }
        }
    }

    private func trend(_ hotspot: Hotspot) -> some View {
        Section("Temperature") {
            Chart {
                ForEach(Severity.thresholds, id: \.0) { threshold in
                    RuleMark(y: .value("Threshold", threshold.1))
                        .foregroundStyle(threshold.0.color.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                ForEach(hotspot.readings, id: \.time) { reading in
                    LineMark(x: .value("Time", reading.time), y: .value("°C", reading.celsius))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Time", reading.time), y: .value("°C", reading.celsius))
                        .symbolSize(20)
                }
                .foregroundStyle(hotspot.severity.color)
            }
            .chartYAxisLabel("°C")
            .frame(height: 160)
            .accessibilityLabel("Temperature trend")
            .accessibilityValue(Text(trendDescription(hotspot)))
        }
    }

    private func whereabouts(_ hotspot: Hotspot) -> some View {
        Section("Location") {
            if let user = location.coordinate {
                LabeledContent("From you", value: Direction(from: user, to: hotspot.coordinate).text)
            }
            Button {
                openInMaps(hotspot)
            } label: {
                Label("Walking directions", systemImage: "figure.walk")
            }
        }
    }

    private func actions(_ hotspot: Hotspot) -> some View {
        Section {
            ForEach(HotspotAction.crewActions.filter(hotspot.workflow.canApply), id: \.self) { action in
                Button {
                    Task { await model.perform(action, on: hotspot.id) }
                } label: {
                    Label(resource: action.label, systemImage: action.symbol)
                        .foregroundStyle(.white)  // icons otherwise take the accent colour
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(action.tint)
                .accessibilityIdentifier("action.\(action.rawValue)")
            }
            .listRowSeparator(.hidden)
        } header: {
            Text("Actions")
        } footer: {
            if model.field.pendingCommands.contains(where: { $0.hotspotID == hotspot.id }) {
                Label(
                    "Saved on this device; it will sync when the connection allows.",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .accessibilityIdentifier("pending")
            }
        }
    }

    private func trendDescription(_ hotspot: Hotspot) -> String {
        guard let first = hotspot.readings.first else { return "" }
        return String(
            localized:
                "From \(Format.temperature(first.celsius)) to \(Format.temperature(hotspot.temperatureCelsius)) over \(hotspot.readings.count) readings"
        )
    }

    private func openInMaps(_ hotspot: Hotspot) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: hotspot.coordinate.clLocation))
        item.name = String(localized: "Hotspot \(Format.temperature(hotspot.temperatureCelsius))")
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}

extension HotspotAction {
    /// Actions crews take; flare-ups come from detection.
    static let crewActions: [HotspotAction] = [.assign, .unassign, .extinguish, .verifyCold]

    var label: LocalizedStringResource {
        switch self {
        case .assign: "Take this hotspot"
        case .unassign: "Hand it back"
        case .extinguish: "Mark extinguished"
        case .verifyCold: "Verify cold"
        case .flareUp: "Flared up"
        }
    }

    var symbol: String {
        switch self {
        case .assign: "hand.raised.fill"
        case .unassign: "arrow.uturn.backward"
        case .extinguish: "drop.fill"
        case .verifyCold: "checkmark.seal.fill"
        case .flareUp: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .assign, .flareUp: .orange
        case .unassign: .gray
        case .extinguish: .blue
        case .verifyCold: .green
        }
    }
}
