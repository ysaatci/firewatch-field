import FireWatchAPI
import FireWatchCore
import Foundation
import SwiftData

/// The fire cache in SwiftData. A ``ModelActor`` written out by hand, because the macro
/// can't take extra properties such as the source key.
actor SwiftDataFieldCache: ModelActor, FieldCache {
    nonisolated let modelContainer: ModelContainer
    nonisolated let modelExecutor: any ModelExecutor
    private let sourceKey: String

    init(container: ModelContainer, sourceKey: String) {
        modelContainer = container
        modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(container))
        self.sourceKey = sourceKey
    }

    func load() -> CachedFire? {
        let key = sourceKey
        let descriptor = FetchDescriptor<CachedFireRecord>(predicate: #Predicate { $0.sourceKey == key })
        guard let record = try? modelContext.fetch(descriptor).first else { return nil }
        let decoder = API.makeDecoder()
        guard var state = try? decoder.decode(SnapshotDTO.self, from: record.snapshot).fireState() else {
            return nil  // written by an incompatible version; the feed will refill it
        }
        if let history = try? decoder.decode(PerimeterHistoryDTO.self, from: record.perimeters) {
            let perimeters = history.features.compactMap { try? FirePerimeter($0) }
            state = FireState(hotspots: state.hotspots.values, drones: state.drones.values, perimeters: perimeters)
        }
        return CachedFire(state: state, asOf: record.asOf, receivedAt: record.receivedAt)
    }

    func save(_ fire: CachedFire) {
        let encoder = API.makeEncoder()
        guard let snapshot = try? encoder.encode(SnapshotDTO(fire.state, generatedAt: fire.asOf)),
            let perimeters = try? encoder.encode(
                PerimeterHistoryDTO(features: fire.state.perimeters.map(PerimeterDTO.init)))
        else { return }
        let key = sourceKey
        try? modelContext.delete(model: CachedFireRecord.self, where: #Predicate { $0.sourceKey == key })
        modelContext.insert(
            CachedFireRecord(
                sourceKey: sourceKey, asOf: fire.asOf, receivedAt: fire.receivedAt, snapshot: snapshot,
                perimeters: perimeters))
        try? modelContext.save()
    }
}

/// The outbox queue in SwiftData, so queued actions survive the app being killed (NFR-3).
actor SwiftDataOutboxStore: ModelActor, OutboxStore {
    nonisolated let modelContainer: ModelContainer
    nonisolated let modelExecutor: any ModelExecutor
    private let sourceKey: String

    init(container: ModelContainer, sourceKey: String) {
        modelContainer = container
        modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(container))
        self.sourceKey = sourceKey
    }

    func load() throws -> [OutboxEntry] {
        let key = sourceKey
        let descriptor = FetchDescriptor<OutboxRecord>(
            predicate: #Predicate { $0.sourceKey == key }, sortBy: [SortDescriptor(\.position)])
        let decoder = API.makeDecoder()
        return try modelContext.fetch(descriptor).compactMap { record in
            guard let stored = try? decoder.decode(StoredOutboxItem.self, from: record.item),
                let item = stored.item
            else { return nil }
            return OutboxEntry(item: item, enqueuedAt: record.enqueuedAt, attempts: record.attempts)
        }
    }

    func save(_ entries: [OutboxEntry]) throws {
        let key = sourceKey
        try modelContext.delete(model: OutboxRecord.self, where: #Predicate { $0.sourceKey == key })
        let encoder = API.makeEncoder()
        for (position, entry) in entries.enumerated() {
            let data = try encoder.encode(StoredOutboxItem(entry.item))
            modelContext.insert(
                OutboxRecord(
                    sourceKey: sourceKey, position: position, enqueuedAt: entry.enqueuedAt, attempts: entry.attempts,
                    item: data))
        }
        try modelContext.save()
    }
}

/// An outbox item as stored: the API's DTOs, plus the local photo file the wire format omits.
enum StoredOutboxItem: Codable {
    case command(CommandDTO)
    case report(ReportDTO, photoFileName: String?)

    init(_ item: OutboxItem) {
        switch item {
        case .command(let command):
            self = .command(CommandDTO(command))
        case .report(let report):
            self = .report(ReportDTO(report, photoJPEG: nil), photoFileName: report.photoFileName)
        }
    }

    /// The item, or `nil` if it no longer maps (for example after a schema change).
    var item: OutboxItem? {
        switch self {
        case .command(let dto):
            return (try? HotspotCommand(dto)).map(OutboxItem.command)
        case .report(let dto, let photoFileName):
            guard var report = try? SightingReport(dto) else { return nil }
            report.photoFileName = photoFileName
            return .report(report)
        }
    }
}
