import XCTest

/// Actions taken with no signal survive the app being killed and sync once it's back (NFR-3).
final class OfflineTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testQueuedActionSurvivesRelaunchAndSyncs() {
        // No signal, and a clean store.
        let app = XCUIApplication.demo(speed: 1)
        app.launchArguments += ["-simulateOutage", "YES", "-resetStorage", "YES"]
        app.launch()
        app.tabBars.buttons["Hotspots"].tap()

        let firstRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'row.'")).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 30))
        let rowID = firstRow.identifier
        firstRow.tap()
        app.buttons["action.assign"].tap()

        // Shown at once, but waiting to sync.
        XCTAssertTrue(app.buttons["action.unassign"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["pending"].firstMatch.waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "08-offline-queued")

        // Kill the app; relaunch with signal back and the same store.
        app.terminate()
        let relaunched = XCUIApplication.demo(speed: 1)
        relaunched.launch()
        relaunched.tabBars.buttons["Hotspots"].tap()
        let row = relaunched.buttons[rowID]
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        row.tap()

        // The queued action was restored, sent and confirmed.
        XCTAssertTrue(relaunched.buttons["action.unassign"].waitForExistence(timeout: 15))
        let pending = relaunched.descendants(matching: .any)["pending"].firstMatch
        let synced = NSPredicate(format: "exists == false")
        expectation(for: synced, evaluatedWith: pending)
        waitForExpectations(timeout: 20)
        attachScreenshot(of: relaunched, named: "09-synced-after-relaunch")
    }
}
