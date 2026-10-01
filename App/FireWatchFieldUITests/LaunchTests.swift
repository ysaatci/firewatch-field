import XCTest

/// Launches the app and keeps screenshots as test attachments. CI exports them, which is
/// how this project sees its UI without a Mac.
final class LaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsTheTabs() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Map"].waitForExistence(timeout: 10))
        attachScreenshot(of: app, named: "01-launch")

        for tab in ["Hotspots", "Report", "Settings"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.navigationBars[tab].waitForExistence(timeout: 5))
        }
    }
}

extension XCTestCase {
    /// Adds a screenshot that is kept even when the test passes.
    @MainActor
    func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
