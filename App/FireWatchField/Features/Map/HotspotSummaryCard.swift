import FireWatchCore
import SwiftUI

/// A compact card for a hotspot tapped on the map.
struct HotspotSummaryCard: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    let hotspotID: Hotspot.ID

    var body: some View {
        if let hotspot = model.field.fire.hotspots[hotspotID] {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(resource: hotspot.severity.label, systemImage: hotspot.severity.symbol)
                        .foregroundStyle(hotspot.severity.color)
                        .font(.headline)
                    Spacer()
                    Label(resource: hotspot.status.label, systemImage: hotspot.status.symbol)
                        .font(.subheadline)
                }
                Text(Format.temperature(hotspot.temperatureCelsius))
                    .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                if let asOf = model.field.asOf {
                    Text("Last measured \(RelativeTime(from: hotspot.lastSeen, to: asOf).text)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Button {
                    dismiss()
                    router.open(hotspotID)
                } label: {
                    Label("Details and actions", systemImage: "chevron.right.circle")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ContentUnavailableView("Hotspot no longer known", systemImage: "questionmark.circle")
        }
    }
}
