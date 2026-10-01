// swift-tools-version: 6.0
import PackageDescription

// The simulator server lives in its own package so the iOS app never resolves Vapor.
let package = Package(
    name: "FireWatchServer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: ".."),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.122.0"),
    ],
    targets: [
        .target(
            name: "FireWatchServer",
            dependencies: [
                .product(name: "FireWatchAPI", package: "firewatch-field"),
                .product(name: "FireWatchSimulator", package: "firewatch-field"),
                .product(name: "Vapor", package: "vapor"),
            ]
        ),
        .executableTarget(name: "firewatch-server", dependencies: ["FireWatchServer"]),
        .testTarget(
            name: "FireWatchServerTests",
            dependencies: ["FireWatchServer", .product(name: "VaporTesting", package: "vapor")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
