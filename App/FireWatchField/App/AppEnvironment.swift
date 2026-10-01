import FireWatchClient
import FireWatchCore
import FireWatchSimulator
import Foundation
import SwiftData

/// Builds the session for a configuration: the one place that knows which concrete feed,
/// sink and storage the app uses (D7).
enum AppEnvironment {
    /// Every source passes through `outage`, so losing signal can be simulated anywhere.
    static func makeSession(
        for configuration: AppConfiguration, container: ModelContainer, outage: Outage
    ) async -> FieldSession {
        let (feed, sink) = await makeSources(for: configuration)
        let key = configuration.source.storageKey
        return FieldSession(
            feed: OutageFeed(wrapping: feed, outage: outage),
            sink: OutageSink(wrapping: sink, outage: outage),
            outboxStore: SwiftDataOutboxStore(container: container, sourceKey: key),
            cache: SwiftDataFieldCache(container: container, sourceKey: key),
            alertRadiusMetres: configuration.alertRadiusMetres
        )
    }

    private static func makeSources(for configuration: AppConfiguration) async -> (
        any DetectionFeed, any CommandSink
    ) {
        switch configuration.source {
        case .demo:
            // Building the scenario takes a moment: keep it off the main thread.
            let feed = await Task.detached(priority: .userInitiated) {
                SimulatedFeed(
                    preset: configuration.demoPreset, speed: configuration.demoSpeed,
                    startMinute: configuration.demoStartMinute)
            }.value
            return (feed, feed)
        case .server(let url, let token):
            let client = APIClient(configuration: .init(baseURL: url, token: token))
            return (ServerFeed(client: client), ServerCommandSink(client: client, loadPhoto: PhotoStore.load))
        }
    }
}
