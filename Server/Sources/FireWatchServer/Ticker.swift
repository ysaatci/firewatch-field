import NIOConcurrencyHelpers
import Vapor

/// Runs `tick` on a fixed interval from boot until shutdown.
final class Ticker: LifecycleHandler, Sendable {
    private let interval: Duration
    private let tick: @Sendable () async -> Void
    private let task = NIOLockedValueBox<Task<Void, Never>?>(nil)

    init(interval: Duration, tick: @escaping @Sendable () async -> Void) {
        self.interval = interval
        self.tick = tick
    }

    func didBootAsync(_ application: Application) async throws {
        let interval = interval
        let tick = tick
        task.withLockedValue {
            $0 = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: interval)
                    await tick()
                }
            }
        }
    }

    func shutdownAsync(_ application: Application) async {
        task.withLockedValue { $0?.cancel() }
    }
}
