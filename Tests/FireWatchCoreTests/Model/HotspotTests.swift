import Foundation
import TestSupport
import Testing

@testable import FireWatchCore

struct HotspotTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func reading(minutes: Double, celsius: Double) -> TemperatureReading {
        TemperatureReading(time: start.addingTimeInterval(minutes * 60), celsius: celsius)
    }

    func makeHotspot() -> Hotspot {
        Hotspot(
            id: "hs-1", coordinate: .manavgat, confidence: 0.8, reading: reading(minutes: 0, celsius: 350))
    }

    @Test func startsWithFirstReading() {
        let hotspot = makeHotspot()
        #expect(hotspot.firstSeen == start)
        #expect(hotspot.lastSeen == start)
        #expect(hotspot.temperatureCelsius == 350)
        #expect(hotspot.status == .new)
    }

    @Test func recordingUpdatesLatestAndConfidence() {
        var hotspot = makeHotspot()
        hotspot.record(reading(minutes: 10, celsius: 120), confidence: 0.6)
        #expect(hotspot.temperatureCelsius == 120)
        #expect(hotspot.lastSeen == start.addingTimeInterval(600))
        #expect(hotspot.firstSeen == start)
        #expect(hotspot.confidence == 0.6)
    }

    @Test func ignoresOutOfOrderReadings() {
        var hotspot = makeHotspot()
        hotspot.record(reading(minutes: 10, celsius: 120), confidence: 0.6)
        hotspot.record(reading(minutes: 5, celsius: 500), confidence: 0.9)
        #expect(hotspot.temperatureCelsius == 120)
        #expect(hotspot.readings.count == 2)
    }

    @Test func historyIsCapped() {
        var hotspot = makeHotspot()
        for minute in 1...100 {
            hotspot.record(reading(minutes: Double(minute), celsius: 300), confidence: 0.8)
        }
        #expect(hotspot.readings.count == Hotspot.historyLimit)
        #expect(hotspot.lastSeen == start.addingTimeInterval(6_000))
        #expect(hotspot.firstSeen == start)
    }

    @Test(arguments: [
        (25.0, Severity.low), (79.9, .low), (80, .moderate), (199, .moderate),
        (200, .high), (399, .high), (400, .extreme), (900, .extreme),
    ])
    func severityFromTemperature(celsius: Double, expected: Severity) {
        #expect(Severity(celsius: celsius) == expected)
    }

    @Test func identifiersCompareByRawValue() {
        let a: Hotspot.ID = "a"
        #expect(a < "b")
        #expect(a.description == "a")
    }
}
