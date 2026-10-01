import XCTest

/// New hotspots near the user raise a banner that leads to the hotspot (FR-8).
final class AlertTests: FireWatchUITestCase {
    @MainActor
    func testNearbyHotspotRaisesBannerThatOpensIt() {
        // Fast replay, so drones find new hotspots within the test. CI puts the simulator
        // by the fire, so they are nearby.
        let app = XCUIApplication.demo(speed: 120, startMinute: 60)
        app.launch()

        let banner = app.descendants(matching: .any)["alertBanner"].firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 90), "no alert within the timeout")
        attachScreenshot(of: app, named: "06-alert-banner")

        XCTAssertTrue(app.descendants(matching: .any)["connection"].firstMatch.exists)

        banner.tap()
        app.swipeUp()  // the actions sit below the summary, chart and location
        let actions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'action.'"))
        XCTAssertTrue(actions.firstMatch.waitForExistence(timeout: 10), "the banner didn't open the hotspot")
        attachScreenshot(of: app, named: "07-alert-opened")
    }
}
