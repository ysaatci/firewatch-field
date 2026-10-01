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

        // The on-device simulator starts well into the fire, so hotspots are known at once,
        // ranked with their distance and direction from the user.
        app.tabBars.buttons["Hotspots"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'row.'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 20))
        let withDistance = NSPredicate(format: "label MATCHES %@", ".*[0-9] (m|km) (N|NE|E|SE|S|SW|W|NW).*")
        expectation(for: withDistance, evaluatedWith: rows.firstMatch)
        waitForExpectations(timeout: 10)
        attachScreenshot(of: app, named: "01-launch")
    }

    @MainActor
    func testMapShowsHotspotsAndPerimeter() {
        let app = XCUIApplication.demo()
        app.launch()
        let markers = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'cluster' OR identifier BEGINSWITH 'hotspot.'"))
        XCTAssertTrue(markers.firstMatch.waitForExistence(timeout: 30))
        sleep(4)  // let satellite tiles load before the screenshot
        attachScreenshot(of: app, named: "02-map")
        XCTAssertTrue(app.sliders["Perimeter time"].exists)
    }
}

extension XCUIApplication {
    /// The app in demo mode at a fixed speed and position, so runs are comparable.
    static func demo(speed: Int = 60, startMinute: Int = 150) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-demoSpeed", "\(speed)", "-demoStartMinute", "\(startMinute)", "-skipNotificationPermission", "YES",
            // By where the demo fire starts, so distances, ranking and alerts are exercised.
            "-fixedLocation", "36.826,31.456",
            "-hasSeenIntro", "YES",
        ]
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
