import FireWatchCore
import SwiftUI

/// How severity and status look everywhere in the app. Severity is never shown by colour
/// alone: each level also has its own shape (NFR-6).
extension Severity {
    var color: Color {
        switch self {
        case .low: .yellow
        case .moderate: .orange
        case .high: .red
        case .extreme: Color(red: 0.55, green: 0.0, blue: 0.35)
        }
    }

    var symbol: String {
        switch self {
        case .low: "circle.fill"
        case .moderate: "square.fill"
        case .high: "triangle.fill"
        case .extreme: "flame.fill"
        }
    }

    var label: LocalizedStringResource {
        switch self {
        case .low: "Low"
        case .moderate: "Moderate"
        case .high: "High"
        case .extreme: "Extreme"
        }
    }
}

extension HotspotStatus {
    var symbol: String {
        switch self {
        case .new: "sparkle"
        case .assigned: "person.fill"
        case .extinguished: "drop.fill"
        case .verifiedCold: "checkmark.seal.fill"
        case .flaredUp: "exclamationmark.triangle.fill"
        }
    }

    var label: LocalizedStringResource {
        switch self {
        case .new: "New"
        case .assigned: "Assigned"
        case .extinguished: "Extinguished"
        case .verifiedCold: "Verified cold"
        case .flaredUp: "Flared up"
        }
    }

    /// Hotspots nobody needs to act on fade back on the map.
    var isSettled: Bool { self == .verifiedCold || self == .extinguished }
}

extension Label where Title == Text, Icon == Image {
    /// A label from a localized resource, such as ``Severity/label``.
    init(resource title: LocalizedStringResource, systemImage: String) {
        self.init {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
        }
    }
}

extension Color {
    /// FireWatch orange, the app-wide tint. Set in code so it can't silently fall back to blue.
    /// Darker in light mode so tinted text keeps 4.5:1 contrast on white (NFR-6).
    static let brand = Color(
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.91, green: 0.42, blue: 0.0, alpha: 1)
                : UIColor(red: 0.76, green: 0.32, blue: 0.0, alpha: 1)
        })
}
