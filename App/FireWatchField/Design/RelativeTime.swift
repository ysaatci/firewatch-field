import Foundation

/// "35 min ago" style text between two feed times. Always measured against the feed's time,
/// never the device clock, because the simulator replays faster than real time.
struct RelativeTime {
    let from: Date
    let to: Date

    var text: String {
        let minutes = Int(max(to.timeIntervalSince(from), 0) / 60)
        if minutes < 1 { return String(localized: "just now") }
        if minutes < 60 { return String(localized: "\(minutes) min ago") }
        return String(localized: "\(minutes / 60) h \(minutes % 60) min ago")
    }
}
