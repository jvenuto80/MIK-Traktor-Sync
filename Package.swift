// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MIKTraktorSync",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MIKTraktorSync", targets: ["MIKTraktorSync"])
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.14.0")
    ],
    targets: [
        .executableTarget(
            name: "MIKTraktorSync",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift")
            ],
            path: "MIKTraktorSync"
        )
    ]
)
