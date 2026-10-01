import FireWatchClient
import FireWatchCore
import FireWatchSimulator
import Foundation

/// Builds the session for a configuration: the one place that knows which concrete feed,
/// sink and storage the app uses (D7).
enum AppEnvironment {
    static func makeSession(for configuration: AppConfiguration) async -> FieldSession {
        let (feed, sink) = await makeSources(for: configuration)
        return FieldSession(
            feed: feed,
            sink: sink,
            outboxStore: InMemoryOutboxStore(),
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
                SimulatedFeed(speed: configuration.demoSpeed, startMinute: configuration.demoStartMinute)
            }.value
            return (feed, feed)
        case .server(let url, let token):
            let client = APIClient(configuration: .init(baseURL: url, token: token))
            return (ServerFeed(client: client), ServerCommandSink(client: client))
        }
    }
}
