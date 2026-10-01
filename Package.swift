// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FireWatchField",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FireWatchCore", targets: ["FireWatchCore"]),
    ],
    targets: [
        // Platform-neutral domain logic: must build on Linux (no Apple-only imports).
        .target(name: "FireWatchCore"),
        .testTarget(name: "FireWatchCoreTests", dependencies: ["FireWatchCore"]),
    ],
    swiftLanguageModes: [.v6]
)
