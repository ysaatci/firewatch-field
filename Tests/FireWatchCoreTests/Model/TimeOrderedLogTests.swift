import Foundation
import Testing

@testable import FireWatchCore

struct TimeOrderedLogTests {
    func reading(_ seconds: Double) -> TemperatureReading {
        TemperatureReading(time: Date(timeIntervalSince1970: seconds), celsius: seconds)
    }

    @Test func keepsNewestWithinLimit() {
        var log = TimeOrderedLog(first: reading(0), limit: 3)
        for second in 1...5 {
            let appended = log.append(reading(Double(second)))
            #expect(appended)
        }
        #expect(log.samples.map(\.celsius) == [3, 4, 5])
        #expect(log.latest.celsius == 5)
    }

    @Test func rejectsOlderAndRepeatedSamples() {
        var log = TimeOrderedLog(first: reading(10), limit: 3)
        let older = log.append(reading(9))
        let repeated = log.append(reading(10))
        #expect(!older)
        #expect(!repeated)
        #expect(log.samples.count == 1)
    }
}
