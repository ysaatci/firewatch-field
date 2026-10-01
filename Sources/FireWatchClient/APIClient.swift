import FireWatchAPI
import FireWatchCore
import Foundation

/// Typed access to the FireWatch API over an ``HTTPTransport``.
public struct APIClient: Sendable {
    public struct Configuration: Hashable, Sendable {
        /// For example `http://localhost:8080`.
        public var baseURL: URL
        public var token: String

        public init(baseURL: URL, token: String) {
            self.baseURL = baseURL
            self.token = token
        }
    }

    public let configuration: Configuration
    private let transport: any HTTPTransport

    public init(configuration: Configuration, transport: any HTTPTransport = URLSessionTransport()) {
        self.configuration = configuration
        self.transport = transport
    }

    /// Everything known now, and the (scenario) time it is valid for.
    public func snapshot() async throws(APIError) -> (state: FireState, asOf: Date) {
        let dto = try await get("snapshot", as: SnapshotDTO.self)
        do {
            return (try dto.fireState(), dto.generatedAt)
        } catch {
            throw .invalidResponse("\(error)")
        }
    }

    public func submit(_ command: HotspotCommand) async throws(APIError) -> SubmissionOutcome {
        let receipt = try await post("commands", CommandDTO(command), as: ReceiptDTO.self)
        return SubmissionOutcome(receipt.outcome)
    }

    public func submit(_ report: SightingReport, photoJPEG: Data?) async throws(APIError) -> SubmissionOutcome {
        let receipt = try await post("reports", ReportDTO(report, photoJPEG: photoJPEG), as: ReceiptDTO.self)
        return SubmissionOutcome(receipt.outcome)
    }

    public func replayStatus() async throws(APIError) -> ReplayStatusDTO {
        try await get("control", as: ReplayStatusDTO.self)
    }

    public func controlReplay(_ request: ReplayControlDTO) async throws(APIError) -> ReplayStatusDTO {
        try await post("control", request, as: ReplayStatusDTO.self)
    }

    /// The WebSocket URL of the event stream.
    public var streamURL: URL {
        var components = URLComponents(url: url(for: "stream"), resolvingAgainstBaseURL: false)
        components?.scheme = configuration.baseURL.scheme == "https" ? "wss" : "ws"
        return components?.url ?? url(for: "stream")
    }

    /// Headers every request carries.
    public var authorizationHeaders: [String: String] {
        ["Authorization": "Bearer \(configuration.token)"]
    }

    // MARK: Plumbing

    private func url(for path: String) -> URL {
        configuration.baseURL.appendingPathComponent(API.pathPrefix).appendingPathComponent(path)
    }

    private func get<T: Decodable>(_ path: String, as type: T.Type) async throws(APIError) -> T {
        try await send(HTTPRequest(method: "GET", url: url(for: path)), as: type)
    }

    private func post<T: Decodable>(_ path: String, _ body: some Encodable, as type: T.Type) async throws(APIError)
        -> T
    {
        let data: Data
        do {
            data = try API.makeEncoder().encode(body)
        } catch {
            throw .invalidRequest("\(error)")
        }
        let request = HTTPRequest(
            method: "POST", url: url(for: path), headers: ["Content-Type": "application/json"], body: data)
        return try await send(request, as: type)
    }

    private func send<T: Decodable>(_ request: HTTPRequest, as type: T.Type) async throws(APIError) -> T {
        var request = request
        request.headers.merge(authorizationHeaders) { _, auth in auth }
        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch {
            throw .unreachable("\(error)")
        }
        guard (200..<300).contains(response.status) else {
            throw .http(
                status: response.status, error: try? API.makeDecoder().decode(ErrorDTO.self, from: response.body))
        }
        do {
            return try API.makeDecoder().decode(T.self, from: response.body)
        } catch {
            throw .invalidResponse("\(error)")
        }
    }
}

/// Why an API call failed.
public enum APIError: Error, Hashable, Sendable {
    /// No response: offline, timed out, or the server is down.
    case unreachable(String)
    /// The server answered with an error status.
    case http(status: Int, error: ErrorDTO?)
    /// The request couldn't be encoded.
    case invalidRequest(String)
    /// The response wasn't what the API promises.
    case invalidResponse(String)

    /// Whether trying again later might succeed.
    public var isTransient: Bool {
        switch self {
        case .unreachable: true
        case .http(let status, _): status == 408 || status == 429 || status >= 500
        case .invalidRequest, .invalidResponse: false
        }
    }

    /// A sentence for the user.
    public var message: String {
        switch self {
        case .unreachable: "The server can't be reached."
        case .http(_, let error?): error.message
        case .http(let status, nil): "The server answered with status \(status)."
        case .invalidRequest, .invalidResponse: "The app and server disagree about the data format."
        }
    }
}
