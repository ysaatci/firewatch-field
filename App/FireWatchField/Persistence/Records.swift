import Foundation
import SwiftData

/// The last known fire state for one data source (D10). Stored as the API's own JSON, so
/// the cache format and the wire format can't drift apart.
@Model
final class CachedFireRecord {
    @Attribute(.unique) var sourceKey: String
    var asOf: Date
    var receivedAt: Date?
    /// A `SnapshotDTO`.
    var snapshot: Data
    /// A `PerimeterHistoryDTO`; snapshots only carry the latest perimeter.
    var perimeters: Data

    init(sourceKey: String, asOf: Date, receivedAt: Date?, snapshot: Data, perimeters: Data) {
        self.sourceKey = sourceKey
        self.asOf = asOf
        self.receivedAt = receivedAt
        self.snapshot = snapshot
        self.perimeters = perimeters
    }
}

/// One queued command or report (D9, NFR-3).
@Model
final class OutboxRecord {
    var sourceKey: String
    /// Order in the queue: items are sent oldest first.
    var position: Int
    var enqueuedAt: Date
    var attempts: Int
    /// A `StoredOutboxItem`.
    var item: Data

    init(sourceKey: String, position: Int, enqueuedAt: Date, attempts: Int, item: Data) {
        self.sourceKey = sourceKey
        self.position = position
        self.enqueuedAt = enqueuedAt
        self.attempts = attempts
        self.item = item
    }
}

enum Storage {
    /// The app's store, or an empty one when the `resetStorage` default is set (UI tests).
    static func makeContainer() -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: false)
        if UserDefaults.standard.bool(forKey: "resetStorage") {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: configuration.url.path + suffix)
            }
        }
        do {
            return try ModelContainer(for: CachedFireRecord.self, OutboxRecord.self, configurations: configuration)
        } catch {
            // A broken store must not stop the app: fall back to memory and start afresh.
            do {
                return try ModelContainer(
                    for: CachedFireRecord.self, OutboxRecord.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            } catch {
                fatalError("Even an in-memory store failed, which only a programming error can cause: \(error)")
            }
        }
    }
}
