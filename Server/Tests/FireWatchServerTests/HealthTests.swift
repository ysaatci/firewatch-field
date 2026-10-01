import Testing
import VaporTesting

@testable import FireWatchServer

struct HealthTests {
    @Test func healthIsOK() async throws {
        try await withTestApp { app, _ in
            try await app.testing().test(.GET, "health") { response in
                #expect(response.status == .ok)
                #expect(response.body.string == "ok")
            }
        }
    }
}
