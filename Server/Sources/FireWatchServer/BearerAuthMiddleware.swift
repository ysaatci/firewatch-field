import Vapor

/// Requires `Authorization: Bearer <token>` with the configured token (D11).
struct BearerAuthMiddleware: AsyncMiddleware {
    let token: String

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let presented = request.headers.bearerAuthorization?.token, Self.matches(presented, token) else {
            throw APIFailure.unauthorized
        }
        return try await next.respond(to: request)
    }

    /// Compares in time that depends only on the lengths, so response timing doesn't reveal
    /// how much of a guessed token was right.
    static func matches(_ presented: String, _ expected: String) -> Bool {
        let a = Array(presented.utf8)
        let b = Array(expected.utf8)
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
