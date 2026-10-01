import FireWatchCore
import SwiftUI

/// Whether data is live, and how old it is when it isn't (FR-9).
struct ConnectionBadge: View {
    let field: FieldState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Label {
                Text(text(at: context.date))
            } icon: {
                Circle().fill(color).frame(width: 8, height: 8)
            }
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("connection")
        }
    }

    private var color: Color {
        switch field.connection {
        case .live: .green
        case .connecting: .yellow
        case .offline: .red
        }
    }

    /// Ages use the device clock: they say how long ago this device last heard from the feed.
    private func text(at now: Date) -> String {
        switch field.connection {
        case .live:
            return String(localized: "Live")
        case .connecting:
            return String(localized: "Connecting…")
        case .offline(let retryAt):
            let retry = max(Int(retryAt.timeIntervalSince(now).rounded(.up)), 0)
            let age = field.receivedAt.map { RelativeTime(from: $0, to: now).text }
            if let age {
                return String(localized: "Offline · data from \(age) · retry in \(retry) s")
            }
            return String(localized: "Offline · retry in \(retry) s")
        }
    }
}
