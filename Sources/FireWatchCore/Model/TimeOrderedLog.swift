import Foundation

/// A value sampled at a point in time.
public protocol Timestamped {
    var time: Date { get }
}

/// The most recent samples of something, oldest first.
///
/// Out-of-order samples are dropped and only the newest `limit` are kept. Never empty.
public struct TimeOrderedLog<Sample: Timestamped & Hashable & Sendable>: Hashable, Sendable {
    public let limit: Int
    public private(set) var samples: [Sample]

    public init(first: Sample, limit: Int) {
        precondition(limit > 0, "limit must be positive")
        self.limit = limit
        self.samples = [first]
    }

    public var latest: Sample { samples[samples.count - 1] }

    /// Appends `sample` unless it is older than ``latest``.
    /// - Returns: Whether `sample` was appended.
    @discardableResult
    public mutating func append(_ sample: Sample) -> Bool {
        guard sample.time >= latest.time else { return false }
        samples.append(sample)
        if samples.count > limit {
            samples.removeFirst(samples.count - limit)
        }
        return true
    }
}
