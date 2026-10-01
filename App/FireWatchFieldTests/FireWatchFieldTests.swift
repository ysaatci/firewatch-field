import Testing

@testable import FireWatchField

struct RootViewTests {
    @Test func everySectionHasATitleAndSymbol() {
        #expect(RootView.Section.allCases.count == 4)
        #expect(Set(RootView.Section.allCases.map(\.symbol)).count == 4)
    }
}
