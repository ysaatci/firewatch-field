import FireWatchAPI
import Vapor

/// Sets up the simulation, routes and middleware, reading settings from the environment.
public func configure(_ app: Application) async throws {
    try await configure(app, configuration: .fromEnvironment())
}

/// Sets up the simulation, routes and middleware with explicit settings.
public func configure(_ app: Application, configuration: ServerConfiguration) async throws {
    app.middleware = Middlewares()
    app.middleware.use(APIErrorMiddleware())

    let services = SimulatorServices(configuration: configuration)
    app.simulator = services
    if let interval = configuration.tickInterval {
        app.lifecycle.use(Ticker(interval: interval) { await services.pump.tick() })
    }

    app.get("health") { _ in "ok" }
    let api = app.grouped(PathComponent(stringLiteral: API.pathPrefix))
    try api.register(collection: FeedController(simulation: services.simulation))
    try api.register(collection: StreamController(hub: services.hub))
    try api.register(collection: CrewController(simulation: services.simulation, hub: services.hub))
    try api.register(collection: ControlController(simulation: services.simulation, hub: services.hub))
}

/// The server's long-lived parts, created once at start-up.
struct SimulatorServices: Sendable {
    let simulation: FireSimulation
    let hub = EventHub()

    init(configuration: ServerConfiguration) {
        simulation = FireSimulation(
            preset: configuration.preset,
            speed: configuration.speed,
            startMinute: configuration.startMinute,
            now: configuration.now
        )
    }

    var pump: StreamPump { StreamPump(simulation: simulation, hub: hub) }
}

extension Application {
    private struct ServicesKey: StorageKey {
        typealias Value = SimulatorServices
    }

    /// The server's services, for code that only has the application (such as tests).
    var simulator: SimulatorServices? {
        get { storage[ServicesKey.self] }
        set { storage[ServicesKey.self] = newValue }
    }
}
