import XCTest

/// Shared setup for UI tests: stop at the first failure, and allow location whenever iOS asks.
/// MapKit's own location features can prompt even though the app uses a fixed test position.
class FireWatchUITestCase: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "Location permission") { alert in
            for label in ["Allow While Using App", "Allow Once"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
    }

    /// The row for `identifier`, scrolling the list until it exists: lists build rows lazily.
    @MainActor
    func row(_ identifier: String, in app: XCUIApplication, maxSwipes: Int = 12) -> XCUIElement {
        let row = app.buttons[identifier]
        for _ in 0..<maxSwipes where !row.exists {
            app.swipeUp()
        }
        return row
    }
}
