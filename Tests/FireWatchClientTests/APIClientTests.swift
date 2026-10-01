import FireWatchAPI
import FireWatchCore
import Foundation
import TestSupport
import Testing

@testable import FireWatchClient

/// Answers requests with canned responses and records what was sent.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [Result<HTTPResponse, any Error>]
    private(set) var requests: [HTTPRequest] = []

    init(_ responses: [Result<HTTPResponse, any Error>]) {
        self.responses = responses
    }

    convenience init(status: Int = 200, json: some Encodable) throws {
        self.init([.success(HTTPResponse(status: status, body: try API.makeEncoder().encode(json)))])
    }

    var sent: [HTTPRequest] { lock.withLock { requests } }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let next: Result<HTTPResponse, any Error> = lock.withLock {
            requests.append(request)
            return responses.isEmpty ? .success(HTTPResponse(status: 500, body: Data())) : responses.removeFirst()
        }
        return try next.get()
    }
}

struct APIClientTests {
    let configuration = APIClient.Configuration(baseURL: URL("http://sim.test:8080"), token: "secret")

    func client(_ transport: FakeTransport) -> APIClient {
        APIClient(configuration: configuration, transport: transport)
    }

    @Test func fetchesSnapshotWithToken() async throws {
        let time = Date(timeIntervalSince1970: 1_800_000_000)
        let transport = try FakeTransport(
            json: SnapshotDTO(generatedAt: time, hotspots: [], drones: [], perimeter: nil))
        let (state, asOf) = try await client(transport).snapshot()
        #expect(state == FireState())
        #expect(asOf == time)
        let request = try #require(transport.sent.first)
        #expect(request.method == "GET")
        #expect(request.url.absoluteString == "http://sim.test:8080/v1/snapshot")
        #expect(request.headers["Authorization"] == "Bearer secret")
    }

    @Test func postsCommandsAsJSON() async throws {
        let transport = try FakeTransport(json: ReceiptDTO(id: "c-1", outcome: .duplicate))
        let command = HotspotCommand(id: "c-1", hotspotID: "hs-1", action: .extinguish, issuedAt: .distantPast)
        #expect(try await client(transport).submit(command) == .duplicate)
        let request = try #require(transport.sent.first)
        #expect(request.method == "POST")
        #expect(request.url.path == "/v1/commands")
        #expect(request.headers["Content-Type"] == "application/json")
        let body = try API.makeDecoder().decode(CommandDTO.self, from: try #require(request.body))
        #expect(body == CommandDTO(command))
    }

    @Test func postsReportsWithPhoto() async throws {
        let transport = try FakeTransport(json: ReceiptDTO(id: "r", outcome: .applied))
        let report = SightingReport(createdAt: .now, coordinate: .manavgat, severity: .high, note: "Smoke")
        _ = try await client(transport).submit(report, photoJPEG: Data([1, 2]))
        let body = try API.makeDecoder().decode(ReportDTO.self, from: try #require(transport.sent.first?.body))
        #expect(body.photoJPEG == Data([1, 2]))
    }

    @Test func errorStatusesCarryTheServerReason() async throws {
        let error = ErrorDTO(code: "notAllowed", message: "verifyCold is not allowed from flaredUp")
        let transport = try FakeTransport(status: 409, json: error)
        let command = HotspotCommand(hotspotID: "hs-1", action: .verifyCold, issuedAt: .now)
        await #expect(throws: APIError.http(status: 409, error: error)) { try await client(transport).submit(command) }
    }

    @Test func networkFailuresAreUnreachableAndTransient() async throws {
        struct Offline: Error {}
        let transport = FakeTransport([.failure(Offline())])
        do {
            _ = try await client(transport).snapshot()
            Issue.record("expected a failure")
        } catch {
            #expect(error.isTransient)
            #expect(error.message == "The server can't be reached.")
        }
    }

    @Test func malformedResponsesAreInvalid() async throws {
        let transport = FakeTransport([.success(HTTPResponse(status: 200, body: Data("{}".utf8)))])
        do {
            _ = try await client(transport).snapshot()
            Issue.record("expected a failure")
        } catch {
            guard case .invalidResponse = error else {
                Issue.record("expected invalidResponse, got \(error)")
                return
            }
            #expect(!error.isTransient)
        }
    }

    @Test(arguments: [(408, true), (429, true), (500, true), (503, true), (400, false), (401, false), (409, false)])
    func transientStatuses(status: Int, transient: Bool) {
        #expect(APIError.http(status: status, error: nil).isTransient == transient)
    }

    @Test func streamURLUsesWebSocketScheme() {
        #expect(client(FakeTransport([])).streamURL.absoluteString == "ws://sim.test:8080/v1/stream")
        let secure = APIClient(
            configuration: .init(baseURL: URL("https://fire.example"), token: "t"),
            transport: FakeTransport([]))
        #expect(secure.streamURL.absoluteString == "wss://fire.example/v1/stream")
    }
}
