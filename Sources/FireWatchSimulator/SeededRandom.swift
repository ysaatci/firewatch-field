/// A deterministic random number generator (SplitMix64).
///
/// Foundation's generators can't be seeded, and the scenario must be identical on every
/// run and platform. The helpers below derive values from raw bits directly rather than
/// through the standard library's `random(in:using:)`, whose algorithm isn't guaranteed.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// An independent generator for one part of the simulation, so drawing more numbers
    /// in one part never shifts the values another part gets.
    public func fork(_ stream: UInt64) -> SeededRandom {
        var mixer = SeededRandom(seed: state ^ (stream &* 0xD1B5_4A32_D192_ED03))
        return SeededRandom(seed: mixer.next())
    }

    /// A uniform value in `0..<1`.
    public mutating func unit() -> Double {
        Double(next() >> 11) * 0x1p-53
    }

    /// A uniform value in `range`.
    public mutating func uniform(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }

    /// `true` with the given probability.
    public mutating func chance(_ probability: Double) -> Bool {
        unit() < probability
    }
}
