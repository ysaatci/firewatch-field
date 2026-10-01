import XCTest

/// A crew member reports a sighting, which waits on the map until it can be sent (FR-7).
final class ReportTests: FireWatchUITestCase {
    @MainActor
    func testReportWaitsOnTheMapWhileOffline() {
        let app = XCUIApplication.demo(speed: 1)
        app.launchArguments += ["-simulateOutage", "YES", "-resetStorage", "YES"]
        app.launch()
        app.tabBars.buttons["Report"].tap()

        let note = app.textViews["note"].exists ? app.textViews["note"] : app.textFields["note"]
        XCTAssertTrue(note.waitForExistence(timeout: 10))
        note.tap()
        note.typeText("Smoke rising behind the ridge")
        app.buttons["High"].tap()
        attachScreenshot(of: app, named: "10-report-form")

        let submit = app.buttons["submitReport"]
        if !submit.isHittable { app.swipeUp() }
        submit.tap()
        XCTAssertTrue(app.descendants(matching: .any)["reportConfirmation"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["queued"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["queuedReport"].firstMatch.waitForExistence(timeout: 5))

        app.tabBars.buttons["Map"].tap()
        sleep(3)  // the pending report shows as a dashed pin; let the map settle for the screenshot
        attachScreenshot(of: app, named: "11-report-pending-on-map")
    }
}
