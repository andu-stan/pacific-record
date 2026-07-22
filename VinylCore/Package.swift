// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VinylCore",
    platforms: [
        // The iOS app target lives in the Xcode project and depends on this
        // package. macOS is declared so the non-UI logic can be built and
        // unit-tested from the command line (`swift test`) on a Mac.
        .iOS(.v17),
        .macOS(.v13),
    ],
    products: [
        .library(name: "VinylCore", targets: ["VinylCore"]),
    ],
    dependencies: [
        // SQLite access with a documented, externally-readable schema.
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0"),
    ],
    targets: [
        .target(
            name: "VinylCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "VinylCoreTests",
            dependencies: ["VinylCore"],
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
