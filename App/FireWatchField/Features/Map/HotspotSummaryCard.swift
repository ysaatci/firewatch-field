import FireWatchCore
import SwiftUI

/// A compact card for a hotspot tapped on the map.
struct HotspotSummaryCard: View {
    @Environment(AppModel.self) private var model
    let hotspotID: Hotspot.ID

    var body: some View {
        if let hotspot = model.field.fire.hotspots[hotspotID] {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(hotspot.severity.label, systemImage: hotspot.severity.symbol)
                        .foregroundStyle(hotspot.severity.color)
                        .font(.headline)
                    Spacer()
                    Label(hotspot.status.label, systemImage: hotspot.status.symbol)
                        .font(.subheadline)
                }
                Text("\(Int(hotspot.temperatureCelsius)) °C")
                    .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                if let asOf = model.field.asOf {
                    Text("Last measured \(RelativeTime(from: hotspot.lastSeen, to: asOf).text)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ContentUnavailableView("Hotspot no longer known", systemImage: "questionmark.circle")
        }
    }
}
