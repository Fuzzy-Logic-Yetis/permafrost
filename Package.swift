// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Permafrost",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PermafrostCore", targets: ["PermafrostCore"]),
        .executable(name: "Permafrost", targets: ["Permafrost"]),
    ],
    dependencies: [
        // The one allowed dependency (ADR-003): SQLite access + FTS5.
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "PermafrostCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .executableTarget(
            name: "Permafrost",
            dependencies: ["PermafrostCore"]
        ),
        .testTarget(
            name: "PermafrostCoreTests",
            dependencies: ["PermafrostCore"]
        ),
        .testTarget(
            name: "PermafrostTests",
            dependencies: ["Permafrost"]
        ),
    ]
)
