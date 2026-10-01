import XCTest

/// A crew member works a hotspot from detection to verified cold (FR-6).
final class HotspotWorkflowTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

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

        let status = app.descendants(matching: .any)["status"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "04-hotspot-detail")

        tap("action.assign", in: app, expecting: "Assigned", status: status)
        tap("action.extinguish", in: app, expecting: "Extinguished", status: status)
        attachScreenshot(of: app, named: "05-hotspot-extinguished")
        tap("action.verifyCold", in: app, expecting: "Verified cold", status: status)
        XCTAssertFalse(app.buttons["action.verifyCold"].exists)
    }

    @MainActor
    private func tap(_ identifier: String, in app: XCUIApplication, expecting label: String, status: XCUIElement) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "\(identifier) missing")
        button.tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", label), evaluatedWith: status)
        waitForExpectations(timeout: 10)
    }
}
