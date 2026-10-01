// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FireWatchField",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FireWatchCore", targets: ["FireWatchCore"]),
        .library(name: "FireWatchSimulator", targets: ["FireWatchSimulator"]),
        .library(name: "FireWatchAPI", targets: ["FireWatchAPI"]),
    ],
    targets: [
        // Platform-neutral domain logic: must build on Linux (no Apple-only imports).
        .target(name: "FireWatchCore"),
        .testTarget(name: "FireWatchCoreTests", dependencies: ["FireWatchCore"]),

        // Deterministic fake-data source: a seeded wildfire scenario.
        .target(name: "FireWatchSimulator", dependencies: ["FireWatchCore"]),
        .testTarget(name: "FireWatchSimulatorTests", dependencies: ["FireWatchSimulator"]),

        // The versioned wire contract shared by the server and the app.
        .target(name: "FireWatchAPI", dependencies: ["FireWatchCore"]),
        .testTarget(name: "FireWatchAPITests", dependencies: ["FireWatchAPI", "FireWatchSimulator"]),
    ],
    swiftLanguageModes: [.v6]
)
