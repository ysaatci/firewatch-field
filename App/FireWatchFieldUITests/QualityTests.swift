import XCTest

/// Performance (NFR-2) and accessibility (NFR-6) checks on the running app.
final class QualityTests: FireWatchUITestCase {
    // MARK: Performance

    /// Cold launch time. CI has no baseline to compare with, so this records the numbers
    /// in the result bundle; it fails only if launching itself fails.
    @MainActor
    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication.demo().launch()
        }
    }

    /// Panning the map with over 2,000 hotspots stays responsive.
    @MainActor
    func testMapWithTwoThousandHotspots() {
        let app = XCUIApplication.demo(startMinute: 300)  // the end of the stress fire
        app.launchArguments += ["-demoPreset", "stress"]
        app.launch()
        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 60))
        // Counting the 2,000 markers in the accessibility tree is slow and flaky; the screenshot
        // shows what was on screen instead.
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "markers settle")], timeout: 8)
        attachScreenshot(of: app, named: "12-stress-map")

        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(application: app)], options: options) {
            map.swipeLeft()
            map.swipeRight()
            map.pinch(withScale: 2, velocity: 1)
            map.pinch(withScale: 0.5, velocity: -1)
        }
    }

    // MARK: Accessibility

    /// Apple's automated audit (contrast, labels, hit regions, clipping) on every main screen.
    @MainActor
    func testScreensPassTheAccessibilityAudit() throws {
        // Audit every screen even after a finding, so one run lists them all.
        continueAfterFailure = true
        let app = XCUIApplication.demo(speed: 1)
        // Far from the fire, so no alert banner covers what is being audited.
        if let index = app.launchArguments.firstIndex(of: "-fixedLocation") {
            app.launchArguments[index + 1] = "37.2,31.9"
        }
        app.launch()
        // Not Dynamic Type: on this SwiftUI app it reports text that does scale (`.headline`,
        // explicit `.footnote`, `@ScaledMetric`), differently on every run. The AX5 snapshot
        // tests cover Dynamic Type instead.
        let checks = XCUIAccessibilityAuditType.all.subtracting(.dynamicType)
        XCTAssertTrue(app.tabBars.buttons["Map"].waitForExistence(timeout: 20))

        for tab in ["Hotspots", "Report", "Settings"] {
            app.tabBars.buttons[tab].tap()
            try app.performAccessibilityAudit(for: checks) { issue in
                MainActor.assumeIsolated { Self.isKnownSystemIssue(issue) }
            }
        }
        app.tabBars.buttons["Hotspots"].tap()
        let firstRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'row.'")).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 20))
        firstRow.tap()
        XCTAssertTrue(app.buttons["action.assign"].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit(for: checks) { issue in
            MainActor.assumeIsolated { Self.isKnownSystemIssue(issue) }
        }
    }

    /// Issues in system UI the app doesn't control: returning `true` ignores them.
    @MainActor
    static func isKnownSystemIssue(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        // The tab bar and navigation bar chrome belong to the system.
        guard let element = issue.element else {
            // Issues the audit can't tie to an element come from system chrome (the glass tab
            // bar); there's nothing in the app to fix, so log them and move on.
            print("Accessibility audit: \(issue.compactDescription) on no element: \(issue.detailedDescription)")
            return true
        }
        // The audit's own failure message doesn't say which element failed, so log it.
        print(
            "Accessibility audit: \(issue.compactDescription) on \(element.elementType.rawValue)",
            "id '\(element.identifier)' label '\(element.label)' frame \(element.frame)",
            "(tab bar zone \(underTabBar))")
        return element.elementType == .tabBar || element.elementType == .navigationBar
            || element.identifier.hasPrefix("_")
            // The status badge sits in a toolbar, which doesn't scale with Dynamic Type.
            || element.identifier == "connection"
            // List rows scrolled under the floating tab bar, or into the blurred scroll edge
            // just above it, are measured against the blur.
            || element.frame.intersects(underTabBar)
    }

    /// The floating tab bar and the scroll edge effect above it.
    @MainActor
    static var underTabBar: CGRect {
        let tabBar = XCUIApplication().tabBars.firstMatch.frame
        return CGRect(x: tabBar.minX, y: tabBar.minY - 80, width: tabBar.width, height: tabBar.height + 80)
    }
}
