import FireWatchCore
import SwiftUI

/// Scrubs back through earlier fire perimeters to see how the fire grew (FR-2).
struct PerimeterTimeline: View {
    let perimeters: [FirePerimeter]
    /// Feed time, which times are shown relative to.
    let asOf: Date?
    /// The perimeter shown; `nil` follows the latest.
    @Binding var index: Int?

    private var lastIndex: Int { perimeters.count - 1 }
    private var current: Int { index ?? lastIndex }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Fire perimeter", systemImage: "clock.arrow.circlepath")
                    .font(.caption.bold())
                Spacer()
                Text(timeLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(index == nil ? .green : .secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(current) },
                    set: { index = Int($0.rounded()) == lastIndex ? nil : Int($0.rounded()) }
                ),
                in: 0...Double(max(lastIndex, 1)),
                step: 1
            )
            .accessibilityLabel("Perimeter time")
            .accessibilityValue(Text(timeLabel))
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    /// "Live", or how long before the feed's current time the shown perimeter was traced.
    private var timeLabel: String {
        guard index != nil, perimeters.indices.contains(current) else { return String(localized: "Live") }
        let time = perimeters[current].time
        return RelativeTime(from: time, to: asOf ?? perimeters[lastIndex].time).text
    }
}
