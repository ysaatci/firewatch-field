import Testing
@testable import FireWatchCore

@Test func versionIsSet() {
    #expect(!FireWatchCore.version.isEmpty)
}
