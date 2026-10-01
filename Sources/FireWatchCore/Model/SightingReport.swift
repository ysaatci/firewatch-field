import Foundation

/// Something a crew member saw and reported from the ground.
public struct SightingReport: Identifiable, Hashable, Sendable {
    public typealias ID = Identifier<SightingReport>

    /// Generated on the device, so retrying a submission never creates a duplicate.
    public let id: ID
    public var createdAt: Date
    public var coordinate: Coordinate
    public var severity: Severity
    public var note: String
    /// Name of the attached photo in the app's local storage, if any.
    public var photoFileName: String?

    public init(
        id: ID = .unique(),
        createdAt: Date,
        coordinate: Coordinate,
        severity: Severity,
        note: String,
        photoFileName: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.coordinate = coordinate
        self.severity = severity
        self.note = note
        self.photoFileName = photoFileName
    }
}

extension Identifier {
    /// A new random identifier, for entities created on this device.
    public static func unique() -> Self {
        Self(UUID().uuidString.lowercased())
    }
}
