import XCTest

/// Launches the app and keeps screenshots as test attachments. CI exports them, which is
/// how this project sees its UI without a Mac.
final class LaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testDemoModeStartsWithHotspots() {
        let app = XCUIApplication.demo()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Map"].waitForExistence(timeout: 10))

        // The on-device simulator starts an hour into the fire, so hotspots are known at once.
        let summary = app.staticTexts["summary"].firstMatch
        let hasHotspots = NSPredicate(format: "label MATCHES %@", "^[1-9][0-9]* hotspots.*")
        expectation(for: hasHotspots, evaluatedWith: summary)
        waitForExpectations(timeout: 20)
        attachScreenshot(of: app, named: "01-launch")

        for tab in ["Hotspots", "Report", "Settings"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.navigationBars[tab].waitForExistence(timeout: 5))
        }
    }
}

extension XCUIApplication {
    /// The app in demo mode at a fixed speed, so runs are comparable.
    static func demo(speed: Int = 60) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-demoSpeed", "\(speed)", "-demoStartMinute", "90"]
        return app
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
