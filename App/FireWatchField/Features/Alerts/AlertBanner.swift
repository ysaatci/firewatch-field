import FireWatchCore
import SwiftUI

/// The newest alert, across the top of the app (FR-8). Tapping it opens the hotspot.
struct AlertBanner: View {
    let alert: HotspotAlert
    let open: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: alert.kind == .flareUp ? "exclamationmark.triangle.fill" : alert.severity.symbol)
                .font(.title2)
                .foregroundStyle(alert.severity.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.headline)
                Text(alert.subtitle)
                    .font(.subheadline)
                    // Not `.secondary`: that is vibrant on the material, and renders black on
                    // black when the banner is drawn off-screen (snapshots) in dark mode.
                    .foregroundStyle(Color.secondaryText)
            }
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.bold())
                    .padding(8)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(alert.severity.color, lineWidth: 2))
        .padding(.horizontal)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("alertBanner")
    }
}

extension HotspotAlert {
    var title: String {
        switch kind {
        case .newHotspot: String(localized: "New \(String(localized: severity.label).lowercased()) hotspot nearby")
        case .flareUp: String(localized: "A hotspot flared up nearby")
        }
    }

    var subtitle: String {
        String(localized: "\(Format.distance(distanceMetres)) from you · tap to open")
    }
}
