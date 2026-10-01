import Foundation

/// Everything the app runs on, wired together:
/// - the feed fills the ``FeedStore``;
/// - the ``Outbox`` sends crew actions, and its queue shows optimistically in the store;
/// - the outbox retries at once when the connection comes back;
/// - new hotspots and flare-ups near the user raise alerts, each once.
///
/// Platform-neutral, so the whole flow is tested on Linux; the app only chooses the feed and sink.
public actor FieldSession {
    public nonisolated let store: FeedStore
    public nonisolated let outbox: Outbox
    private let feed: any DetectionFeed
    private let cache: (any FieldCache)?
    /// Saving every update would be wasteful; at most once per interval (seconds).
    private let cacheInterval: TimeInterval
    private var lastCacheSave: Date?
    private var alertEngine: AlertEngine
    private let now: @Sendable () -> Date
    private var userLocation: Coordinate?
    private var lastFire = FireState()
    private var alerted: Set<String> = []
    private var tasks: [Task<Void, Never>] = []
    private let alertBroadcast = Broadcast<HotspotAlert>()
    private let rejectionBroadcast = Broadcast<Rejection>()

    /// A crew action or report the server refused, to show to the user.
    public struct Rejection: Hashable, Sendable {
        public var item: OutboxItem
        public var reason: String
    }

    public init(
        feed: any DetectionFeed,
        sink: any CommandSink,
        outboxStore: any OutboxStore,
        cache: (any FieldCache)? = nil,
        cacheInterval: TimeInterval = 30,
        alertRadiusMetres: Double = 2_000,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.feed = feed
        self.store = FeedStore(now: now)
        self.outbox = Outbox(store: outboxStore, sink: sink, now: now)
        self.cache = cache
        self.cacheInterval = cacheInterval
        self.alertEngine = AlertEngine(radiusMetres: alertRadiusMetres)
        self.now = now
    }

    /// Shows the cached state, restores the saved outbox and starts the background work. Call once.
    public func start() async {
        if let cached = await cache?.load() {
            await store.restore(cached)
        }
        try? await outbox.restore()
        let store = store
        let outbox = outbox
        let feed = feed
        tasks = [
            Task { await store.follow(feed) },
            Task { await outbox.run() },
            Task { [weak self] in
                for await event in outbox.events() { await self?.handle(event) }
            },
            Task { [weak self] in
                for await state in store.states() { await self?.handle(state) }
            },
        ]
    }

    /// Stops the background work.
    public func stop() {
        for task in tasks { task.cancel() }
        tasks = []
    }

    /// Saves the current state now, for example when the app goes to the background.
    public func saveCache() async {
        guard let cache, let fire = await store.cacheable else { return }
        await cache.save(fire)
        lastCacheSave = now()
    }

    /// New hotspots and flare-ups near the user.
    public nonisolated func alerts() -> AsyncStream<HotspotAlert> {
        alertBroadcast.subscribe().stream
    }

    /// Actions and reports the server refused.
    public nonisolated func rejections() -> AsyncStream<Rejection> {
        rejectionBroadcast.subscribe().stream
    }

    public func perform(_ action: HotspotAction, on hotspot: Hotspot.ID) async {
        await outbox.enqueue(.command(HotspotCommand(hotspotID: hotspot, action: action, issuedAt: now())))
    }

    public func submit(_ report: SightingReport) async {
        await outbox.enqueue(.report(report))
    }

    /// Where the user is, for alerts. `nil` when unknown, which turns alerts off.
    public func setUserLocation(_ location: Coordinate?) {
        userLocation = location
    }

    public func setAlertRadius(metres: Double) {
        alertEngine.radiusMetres = metres
    }

    // MARK: Wiring

    private func handle(_ event: OutboxEvent) async {
        switch event {
        case .pending(let entries):
            let commands = entries.compactMap { entry -> HotspotCommand? in
                guard case .command(let command) = entry.item else { return nil }
                return command
            }
            await store.setPending(commands, queuedReports: entries.count - commands.count)
        case .rejected(let item, let reason):
            rejectionBroadcast.yield(Rejection(item: item, reason: reason))
        }
    }

    private func handle(_ state: FieldState) async {
        if state.connection == .live { await outbox.retryNow() }
        let dueForSave = lastCacheSave.map { now().timeIntervalSince($0) >= cacheInterval } ?? true
        if dueForSave, state.asOf != nil { await saveCache() }
        for alert in alertEngine.alerts(from: lastFire, to: state.fire, near: userLocation)
        where alerted.insert(alert.id).inserted {
            alertBroadcast.yield(alert)
        }
        lastFire = state.fire
    }
}
