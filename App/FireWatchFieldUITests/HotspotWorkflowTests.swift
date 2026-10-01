import XCTest

/// A crew member works a hotspot from detection to verified cold (FR-6).
final class HotspotWorkflowTests: FireWatchUITestCase {
    @MainActor
    func testAssignExtinguishAndVerify() {
        // Slow replay, so the hotspot doesn't flare up mid-test.
        let app = XCUIApplication.demo(speed: 1)
        app.launch()
        app.tabBars.buttons["Hotspots"].tap()

        let firstRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'row.'")).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 30))
        attachScreenshot(of: app, named: "03-hotspot-list")
        firstRow.tap()
        XCTAssertTrue(app.buttons["action.assign"].waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "04-hotspot-detail")

        // Each step offers exactly the next actions the workflow allows.
        // (The status label can scroll out of the lazily built list, so the buttons are checked instead.)
        tap("action.assign", in: app, thenOffers: ["action.unassign", "action.extinguish"])
        tap("action.extinguish", in: app, thenOffers: ["action.verifyCold"])
        attachScreenshot(of: app, named: "05-hotspot-extinguished")
        tap("action.verifyCold", in: app, thenOffers: [])
    }

    @MainActor
    private func tap(_ identifier: String, in app: XCUIApplication, thenOffers expected: [String]) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "\(identifier) missing")
        button.tap()
        for next in expected {
            XCTAssertTrue(app.buttons[next].waitForExistence(timeout: 10), "\(next) not offered after \(identifier)")
        }
        let actions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'action.'"))
        let onlyExpected = NSPredicate { _, _ in actions.count == expected.count }
        expectation(for: onlyExpected, evaluatedWith: nil)
        waitForExpectations(timeout: 10)
    }
}
