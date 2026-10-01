import FireWatchCore
import FireWatchSimulator
import SnapshotTesting
import SwiftUI
import XCTest

@testable import FireWatchField

/// Screens rendered in light, dark and the largest accessibility text size (NFR-6, D14), in
/// whichever language the run uses: CI runs this class once in English and once in Turkish
/// (NFR-7). Set `SNAPSHOT_RECORD=1` (as `TEST_RUNNER_SNAPSHOT_RECORD` for xcodebuild) to
/// record new reference images.
@MainActor
final class SnapshotTests: XCTestCase {
    /// A fixed moment of the demo fire, so the images never change unless the code does.
    static let field: FieldState = {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let world = SimulatedWorld(scenario: Scenario(ScenarioPreset.manavgat.configuration), start: start)
        var field = FieldState.empty
        field.fire = FireState(events: world.events(fromMinute: 0, toMinute: 150))
        field.asOf = world.date(atMinute: 150)
        field.connection = .live
        return field
    }()

    static let variants: [(name: String, traits: UITraitCollection)] = [
        ("light", UITraitCollection(userInterfaceStyle: .light)),
        ("dark", UITraitCollection(userInterfaceStyle: .dark)),
        ("ax5", UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)),
    ]

    var language: String { Locale.current.language.languageCode?.identifier ?? "en" }

    override func invokeTest() {
        let record = ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"
        withSnapshotTesting(record: record ? .all : .missing) { super.invokeTest() }
    }

    private func assertScreens(
        _ view: some View, named name: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let model = AppModel(previewing: Self.field)
        let screen =
            view
            .environment(model)
            .environment(Router())
            .environment(LocationProvider())
        for variant in Self.variants {
            assertSnapshot(
                of: UIHostingController(rootView: screen),
                as: .image(on: .iPhone13Pro, traits: variant.traits),
                named: "\(name)-\(variant.name)-\(language)",
                file: file, line: line)
        }
    }

    private var topHotspot: Hotspot {
        PriorityRanker().ranked(Self.field.fire.hotspots.values, now: Self.field.asOf ?? .now, userLocation: nil)[0]
    }

    func testHotspotList() {
        assertScreens(NavigationStack { HotspotListScreen() }, named: "hotspot-list")
    }

    func testHotspotDetail() {
        assertScreens(NavigationStack { HotspotDetailScreen(hotspotID: topHotspot.id) }, named: "hotspot-detail")
    }

    func testAlertBanner() {
        let alert = HotspotAlert(
            kind: .newHotspot, hotspotID: topHotspot.id, severity: .high, distanceMetres: 640, flareUps: 0)
        assertScreens(
            VStack {
                AlertBanner(alert: alert, open: {}, dismiss: {})
                Spacer()
            }
            .padding(.top, 60),
            named: "alert-banner")
    }

    func testIntro() {
        assertScreens(IntroSheet(), named: "intro")
    }

    func testSettings() {
        assertScreens(NavigationStack { SettingsScreen() }, named: "settings")
    }
}
