import FireWatchAPI
import Testing
import VaporTesting

@testable import FireWatchServer

struct AuthTests {
    static let endpoints: [(HTTPMethod, String)] = [
        (.GET, "v1/snapshot"), (.GET, "v1/hotspots"), (.GET, "v1/perimeters"), (.GET, "v1/drones"),
        (.GET, "v1/stream"), (.POST, "v1/commands"), (.POST, "v1/reports"), (.GET, "v1/control"),
        (.POST, "v1/control"), (.GET, "v1/control/faults"), (.POST, "v1/control/faults"),
        (.POST, "v1/control/disconnect"),
    ]

    @Test(arguments: endpoints)
    func everyEndpointNeedsTheToken(method: HTTPMethod, path: String) async throws {
        try await withTestApp { app, _ in
            for token in [nil, "wrong-token", "test-toke"] {
                let response = try await app.send(method, path, token: token)
                #expect(response.status == .unauthorized, "\(method) \(path) with \(token ?? "no token")")
                #expect(try response.decoded(as: ErrorDTO.self).code == "unauthorized")
            }
        }
    }

    @Test func healthNeedsNoToken() async throws {
        try await withTestApp { app, _ in
            let response = try await app.send(.GET, "health", token: nil)
            #expect(response.status == .ok)
        }
    }

    @Test func tokenComparison() {
        #expect(BearerAuthMiddleware.matches("abc", "abc"))
        #expect(!BearerAuthMiddleware.matches("abd", "abc"))
        #expect(!BearerAuthMiddleware.matches("ab", "abc"))
        #expect(!BearerAuthMiddleware.matches("", "abc"))
    }
}
