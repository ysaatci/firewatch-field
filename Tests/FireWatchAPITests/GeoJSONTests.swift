import Foundation
import Testing

@testable import FireWatchAPI

struct GeoJSONTests {
    struct Name: Hashable, Sendable, Codable {
        var name: String
    }

    func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    let square: [[Position]] = [
        [
            Position(longitude: 0, latitude: 0), Position(longitude: 1, latitude: 0),
            Position(longitude: 1, latitude: 1), Position(longitude: 0, latitude: 0),
        ]
    ]

    @Test func positionIsLongitudeLatitudeArray() throws {
        #expect(try json(Position(longitude: 31.4, latitude: 36.8)) == "[31.4,36.8]")
    }

    @Test func positionIgnoresAltitude() throws {
        let position = try JSONDecoder().decode(Position.self, from: Data("[31.4,36.8,120]".utf8))
        #expect(position == Position(longitude: 31.4, latitude: 36.8))
    }

    @Test func pointEncodesPerSpec() throws {
        #expect(
            try json(Geometry.point(Position(longitude: 1, latitude: 2))) == #"{"coordinates":[1,2],"type":"Point"}"#)
    }

    @Test(arguments: [
        Geometry.point(Position(longitude: 1, latitude: 2)),
        .polygon([[Position(longitude: 0, latitude: 0), Position(longitude: 1, latitude: 1)]]),
        .multiPolygon([[[Position(longitude: 0, latitude: 0)]]]),
    ])
    func geometriesRoundTrip(geometry: Geometry) throws {
        #expect(try roundTrip(geometry) == geometry)
    }

    @Test func rejectsUnsupportedGeometry() {
        let line = Data(#"{"type":"LineString","coordinates":[[0,0],[1,1]]}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Geometry.self, from: line) }
    }

    @Test func featureCollectionRoundTripsAndTagsTypes() throws {
        let collection = FeatureCollection(features: [
            Feature(id: "a", geometry: .polygon(square), properties: Name(name: "burn")),
            Feature(geometry: .point(Position(longitude: 1, latitude: 1)), properties: Name(name: "spot")),
        ])
        #expect(try roundTrip(collection) == collection)
        let text = try json(collection)
        #expect(text.hasPrefix(#"{"features":[{"geometry""#))
        #expect(text.contains(#""type":"FeatureCollection""#))
        #expect(text.contains(#""type":"Feature""#))
    }

    @Test func featureRejectsWrongType() {
        let data = Data(
            #"{"type":"Feature2","geometry":{"type":"Point","coordinates":[0,0]},"properties":{"name":"x"}}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Feature<Name>.self, from: data) }
    }
}
