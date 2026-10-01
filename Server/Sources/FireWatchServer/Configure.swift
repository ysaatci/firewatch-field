import Vapor

/// Sets up routes and middleware on `app`.
public func configure(_ app: Application) async throws {
    app.get("health") { _ in "ok" }
}
