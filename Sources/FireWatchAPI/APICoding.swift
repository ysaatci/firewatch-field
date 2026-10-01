import Foundation

/// Version and encoding rules shared by every API payload.
public enum API {
    /// Bumped on any breaking change to the payloads. Clients reject versions they don't know.
    public static let schemaVersion = 1
    /// Prefix of every endpoint path.
    public static let pathPrefix = "v1"

    /// Dates are ISO 8601 with millisecond precision; keys are sorted so output is stable.
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(dateStyle))
        }
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            // Accept dates without fractional seconds too, as other tools often write them.
            if let date = (try? dateStyle.parse(text)) ?? (try? plainDateStyle.parse(text)) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO 8601 date \(text)")
        }
        return decoder
    }

    private static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plainDateStyle = Date.ISO8601FormatStyle()
}
