import Testing

@testable import FireWatchSimulator

struct SeededRandomTests {
    func draws(_ random: SeededRandom, count: Int) -> [UInt64] {
        var random = random
        return (0..<count).map { _ in random.next() }
    }

    @Test func matchesSplitMix64ReferenceOutput() {
        // Reference values for seed 0 from the SplitMix64 C implementation.
        #expect(draws(SeededRandom(seed: 0), count: 2) == [0xE220_A839_7B1D_CDAF, 0x6E78_9E6A_A1B9_65F4])
    }

    @Test func sameSeedSameSequence() {
        #expect(draws(SeededRandom(seed: 42), count: 100) == draws(SeededRandom(seed: 42), count: 100))
    }

    @Test func forksAreIndependentOfLaterDraws() {
        var random = SeededRandom(seed: 7)
        let fork = random.fork(1)
        _ = random.next()
        #expect(draws(fork, count: 5) == draws(SeededRandom(seed: 7).fork(1), count: 5))
        #expect(draws(fork, count: 5) != draws(SeededRandom(seed: 7).fork(2), count: 5))
    }

    @Test func helpersStayInRange() {
        var random = SeededRandom(seed: 3)
        var units: [Double] = []
        var uniforms: [Double] = []
        for _ in 0..<1_000 {
            units.append(random.unit())
            uniforms.append(random.uniform(5...6))
        }
        let never = random.chance(0)
        let always = random.chance(1)
        #expect(units.allSatisfy { (0..<1).contains($0) })
        #expect(uniforms.allSatisfy { (5...6).contains($0) })
        #expect(!never)
        #expect(always)
    }
}
