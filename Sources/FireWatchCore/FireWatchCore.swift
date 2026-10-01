/// Platform-neutral domain logic for FireWatch Field.
///
/// This module must not import Apple-only frameworks (UIKit, SwiftUI, MapKit,
/// CoreLocation, SwiftData) so it builds and tests on Linux.
public enum FireWatchCore {
    /// Version of the core library, reported in diagnostics.
    public static let version = "0.1.0"
}
