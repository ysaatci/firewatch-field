/// GeoJSON (RFC 7946) types: the format GIS tools and the drone pipeline exchange geometry in.

/// A position, encoded as `[longitude, latitude]`.
public struct Position: Hashable, Sendable, Codable {
    public var longitude: Double
    public var latitude: Double

    public init(longitude: Double, latitude: Double) {
        self.longitude = longitude
        self.latitude = latitude
    }

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        longitude = try container.decode(Double.self)
        latitude = try container.decode(Double.self)
        // An optional altitude may follow; it is ignored.
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(longitude)
        try container.encode(latitude)
    }
}

/// The geometry kinds this API uses. Polygon rings are closed: the last position repeats the first.
public enum Geometry: Hashable, Sendable, Codable {
    case point(Position)
    case polygon([[Position]])
    case multiPolygon([[[Position]]])

    private enum CodingKeys: String, CodingKey {
        case type, coordinates
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "Point": self = .point(try container.decode(Position.self, forKey: .coordinates))
        case "Polygon": self = .polygon(try container.decode([[Position]].self, forKey: .coordinates))
        case "MultiPolygon": self = .multiPolygon(try container.decode([[[Position]]].self, forKey: .coordinates))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container, debugDescription: "Unsupported geometry type \(type)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .point(let position):
            try container.encode("Point", forKey: .type)
            try container.encode(position, forKey: .coordinates)
        case .polygon(let rings):
            try container.encode("Polygon", forKey: .type)
            try container.encode(rings, forKey: .coordinates)
        case .multiPolygon(let polygons):
            try container.encode("MultiPolygon", forKey: .type)
            try container.encode(polygons, forKey: .coordinates)
        }
    }
}

/// A geometry with properties.
public struct Feature<Properties: Hashable & Sendable & Codable>: Hashable, Sendable, Codable {
    public var id: String?
    public var geometry: Geometry
    public var properties: Properties

    public init(id: String? = nil, geometry: Geometry, properties: Properties) {
        self.id = id
        self.geometry = geometry
        self.properties = properties
    }

    private enum CodingKeys: String, CodingKey {
        case type, id, geometry, properties
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.expectType("Feature", forKey: .type)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        geometry = try container.decode(Geometry.self, forKey: .geometry)
        properties = try container.decode(Properties.self, forKey: .properties)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("Feature", forKey: .type)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(geometry, forKey: .geometry)
        try container.encode(properties, forKey: .properties)
    }
}

/// A list of features: what tools like geojson.io open directly.
public struct FeatureCollection<Properties: Hashable & Sendable & Codable>: Hashable, Sendable, Codable {
    public var features: [Feature<Properties>]

    public init(features: [Feature<Properties>]) {
        self.features = features
    }

    private enum CodingKeys: String, CodingKey {
        case type, features
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.expectType("FeatureCollection", forKey: .type)
        features = try container.decode([Feature<Properties>].self, forKey: .features)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("FeatureCollection", forKey: .type)
        try container.encode(features, forKey: .features)
    }
}

extension KeyedDecodingContainer {
    /// Throws unless the string at `key` is `expected`.
    func expectType(_ expected: String, forKey key: Key) throws {
        let type = try decode(String.self, forKey: key)
        guard type == expected else {
            throw DecodingError.dataCorruptedError(
                forKey: key, in: self, debugDescription: "Expected type \(expected), found \(type)")
        }
    }
}
