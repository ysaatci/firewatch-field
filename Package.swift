// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FireWatchField",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FireWatchCore", targets: ["FireWatchCore"]),
        .library(name: "FireWatchSimulator", targets: ["FireWatchSimulator"]),
        .library(name: "FireWatchAPI", targets: ["FireWatchAPI"]),
        .executable(name: "fwgen", targets: ["fwgen"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        // Platform-neutral domain logic: must build on Linux (no Apple-only imports).
        .target(name: "FireWatchCore"),
        .target(name: "TestSupport", dependencies: ["FireWatchCore"], path: "Tests/TestSupport"),
        .testTarget(name: "FireWatchCoreTests", dependencies: ["FireWatchCore", "TestSupport"]),

        // Deterministic fake-data source: a seeded wildfire scenario.
        .target(name: "FireWatchSimulator", dependencies: ["FireWatchCore"]),
        .testTarget(name: "FireWatchSimulatorTests", dependencies: ["FireWatchSimulator", "TestSupport"]),

        // The versioned wire contract shared by the server and the app.
        .target(name: "FireWatchAPI", dependencies: ["FireWatchCore"]),
        .testTarget(name: "FireWatchAPITests", dependencies: ["FireWatchAPI", "FireWatchSimulator", "TestSupport"]),

        // CLI that exports scenarios as API JSON fixtures.
        .executableTarget(
            name: "fwgen",
            dependencies: [
                "FireWatchSimulator", "FireWatchAPI",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
