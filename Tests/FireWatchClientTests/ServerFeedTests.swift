import FireWatchAPI
import FireWatchCore
import FireWatchSimulator
import Foundation
import TestSupport
import Testing

@testable import FireWatchClient

struct ServerFeedTests {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)
    let configuration = APIClient.Configuration(baseURL: URL("http://sim.test"), token: "t")

    /// Real events from a small simulated fire.
    static let events: [FeedEvent] = {
        let scenario = Scenario(
            ScenarioConfiguration(seed: 3, centre: .manavgat, rows: 40, columns: 40, minutes: 60))
        let world = SimulatedWorld(scenario: scenario, start: start)
        return world.events(fromMinute: 0, toMinute: 60)
    }()

    func at(_ minute: Double) -> Date { Self.start.addingTimeInterval(minute * 60) }

    func snapshotResponse(upTo minute: Double) throws -> Result<HTTPResponse, any Error> {
        let state = FireState(events: Self.events.filter { $0.time < at(minute) })
        let body = try API.makeEncoder().encode(SnapshotDTO(state, generatedAt: at(minute)))
        return .success(HTTPResponse(status: 200, body: body))
    }

    func message(_ events: [FeedEvent]) throws -> String {
        String(decoding: try API.makeEncoder().encode(EventBatchDTO(events)), as: UTF8.self)
    }

    func feed(_ transport: FakeTransport, _ steps: [ScriptedConnector.Step]) -> ServerFeed {
        let socket = ReconnectingSocket(
            connector: ScriptedConnector(steps), random: { 0 }, sleep: { _ in })
        return ServerFeed(
            client: APIClient(configuration: configuration, transport: transport), socket: socket,
            now: { Self.start })
    }

    @Test func snapshotThenNewerEventsOnly() async throws {
        let older = Self.events.filter { $0.time < at(20) }.suffix(3)
        let newer = Self.events.filter { $0.time >= at(20) && $0.time < at(25) }
        let transport = FakeTransport([try snapshotResponse(upTo: 20)])
        let feed = feed(transport, [.connect([try message(Array(older)), try message(newer)])])

        var updates: [FeedUpdate] = []
        for await update in feed.updates().prefix(4) { updates.append(update) }
        #expect(updates[0] == .connection(.connecting))
        guard case .snapshot(_, let asOf) = updates[1] else {
            Issue.record("expected a snapshot")
            return
        }
        #expect(asOf == at(20))
        #expect(updates[2] == .connection(.live))
        #expect(updates[3] == .events(newer))  // the buffered older batch was dropped
    }

    @Test func freshSnapshotAfterReconnect() async throws {
        let transport = FakeTransport([try snapshotResponse(upTo: 10), try snapshotResponse(upTo: 30)])
        let feed = feed(transport, [.connect([]), .connect([])])
        var snapshots: [Date] = []
        var sawOffline = false
        for await update in feed.updates().prefix(7) {
            if case .snapshot(_, let asOf) = update { snapshots.append(asOf) }
            if case .connection(.offline) = update { sawOffline = true }
        }
        #expect(snapshots == [at(10), at(30)])
        #expect(sawOffline)
    }

    @Test func failedSnapshotIsRetriedOnTheNextMessage() async throws {
        struct Offline: Error {}
        let transport = FakeTransport([.failure(Offline()), try snapshotResponse(upTo: 5)])
        let newer = Self.events.filter { $0.time >= at(5) && $0.time < at(6) }
        let feed = feed(transport, [.connect([try message(newer)])])
        var updates: [FeedUpdate] = []
        for await update in feed.updates().prefix(5) { updates.append(update) }
        #expect(updates[1] == .connection(.offline(retryAt: Self.start.addingTimeInterval(5))))
        #expect(updates[3] == .connection(.live))
        #expect(updates[4] == .events(newer))
    }

    @Test func malformedMessagesAreSkipped() {
        #expect(ServerFeed.decode("not json").isEmpty)
        #expect(ServerFeed.decode(#"{"schemaVersion":99,"events":[]}"#).isEmpty)
    }

    @Test func sinkMapsFailuresToRetryOrReject() async throws {
        struct Offline: Error {}
        let error = ErrorDTO(code: "notAllowed", message: "verifyCold is not allowed from flaredUp")
        let transport = FakeTransport([
            .failure(Offline()),
            .success(HTTPResponse(status: 409, body: try API.makeEncoder().encode(error))),
            .success(
                HTTPResponse(status: 200, body: try API.makeEncoder().encode(ReceiptDTO(id: "c", outcome: .applied)))),
        ])
        let sink = ServerCommandSink(client: APIClient(configuration: configuration, transport: transport))
        let command = HotspotCommand(id: "c", hotspotID: "hs", action: .verifyCold, issuedAt: .now)
        await #expect(throws: SubmissionError.unavailable) { try await sink.submit(command) }
        await #expect(throws: SubmissionError.rejected(error.message)) { try await sink.submit(command) }
        #expect(try await sink.submit(command) == .applied)
    }

    @Test func sinkAttachesReportPhotos() async throws {
        let transport = try FakeTransport(json: ReceiptDTO(id: "r", outcome: .applied))
        let sink = ServerCommandSink(
            client: APIClient(configuration: configuration, transport: transport),
            loadPhoto: { $0 == "photo.jpg" ? Data([0xFF, 0xD8]) : nil })
        let report = SightingReport(
            createdAt: .now, coordinate: .manavgat, severity: .low, note: "", photoFileName: "photo.jpg")
        _ = try await sink.submit(report)
        let sent = try API.makeDecoder().decode(ReportDTO.self, from: try #require(transport.sent.first?.body))
        #expect(sent.photoJPEG == Data([0xFF, 0xD8]))
    }
}
