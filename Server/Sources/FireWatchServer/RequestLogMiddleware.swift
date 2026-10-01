import Vapor

/// Logs method, path, status and duration. Never the query string or body, which can hold
/// coordinates, nor headers, which hold the token (NFR-8).
struct RequestLogMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let started = ContinuousClock.now
        let response = try await next.respond(to: request)
        let milliseconds = Int((ContinuousClock.now - started) / .milliseconds(1))
        request.logger.info("\(request.method) \(request.url.path) → \(response.status.code) in \(milliseconds) ms")
        return response
    }
}
