import Testing

extension AsyncSequence {
    /// Every element, in order. Only for sequences that end, such as `prefix(_:)`.
    public func collect() async rethrows -> [Element] {
        try await reduce(into: []) { $0.append($1) }
    }
}

/// Polls `condition` until it holds, failing the test after `timeout`.
public func eventually(timeout: Duration = .seconds(5), _ condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !(await condition()) {
        guard ContinuousClock.now < deadline else {
            Issue.record("Condition not met within \(timeout)")
            return
        }
        try await Task.sleep(for: .milliseconds(5))
    }
}
