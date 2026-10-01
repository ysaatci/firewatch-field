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

    let simulation = FireSimulation(
        preset: configuration.preset,
        speed: configuration.speed,
        startMinute: configuration.startMinute,
        now: configuration.now
    )
    app.simulation = simulation
    if let interval = configuration.tickInterval {
        app.lifecycle.use(Ticker(interval: interval) { _ = await simulation.advance() })
    }

    app.get("health") { _ in "ok" }
    let api = app.grouped(PathComponent(stringLiteral: API.pathPrefix))
    try api.register(collection: FeedController(simulation: simulation))
    try api.register(collection: ControlController(simulation: simulation))
}

extension Application {
    private struct SimulationKey: StorageKey {
        typealias Value = FireSimulation
    }

    /// The running simulation, for code that only has the application (such as tests).
    var simulation: FireSimulation? {
        get { storage[SimulationKey.self] }
        set { storage[SimulationKey.self] = newValue }
    }
}
