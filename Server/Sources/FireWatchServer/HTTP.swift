import FireWatchAPI
import Vapor

/// A failure the client should see, rendered as an ``ErrorDTO`` with the given status.
struct APIFailure: Error, Hashable, Sendable {
    let status: HTTPResponseStatus
    let code: String
    let message: String

    static func invalidPayload(_ message: String) -> APIFailure {
        APIFailure(status: .badRequest, code: "invalidPayload", message: message)
    }

    static let unauthorized = APIFailure(
        status: .unauthorized, code: "unauthorized", message: "Missing or wrong bearer token")
}

extension Request {
    /// Decodes the body with the API's own decoder (ISO 8601 dates with milliseconds).
    func decodeBody<T: Decodable>(_ type: T.Type) throws(APIFailure) -> T {
        guard let body = body.data else { throw .invalidPayload("Missing request body") }
        do {
            return try API.makeDecoder().decode(T.self, from: body)
        } catch {
            throw .invalidPayload("Body is not a valid \(T.self): \(error)")
        }
    }
}

extension Response {
    /// A JSON response encoded with the API's own encoder.
    static func json(_ value: some Encodable, status: HTTPResponseStatus = .ok) throws -> Response {
        let response = Response(status: status, body: .init(data: try API.makeEncoder().encode(value)))
        response.headers.contentType = .json
        return response
    }
}

/// Renders every error as an ``ErrorDTO`` body, so clients only ever parse one error shape.
struct APIErrorMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        do {
            return try await next.respond(to: request)
        } catch let failure as APIFailure {
            return try Response.json(ErrorDTO(code: failure.code, message: failure.message), status: failure.status)
        } catch let abort as any AbortError {
            let code = abort.status == .notFound ? "notFound" : "httpError"
            return try Response.json(ErrorDTO(code: code, message: abort.reason), status: abort.status)
        } catch {
            request.logger.report(error: error)
            return try Response.json(
                ErrorDTO(code: "internal", message: "Internal server error"), status: .internalServerError)
        }
    }
}
