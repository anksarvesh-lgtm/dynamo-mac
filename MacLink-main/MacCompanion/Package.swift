// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacCompanion",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacCompanion", targets: ["MacCompanion"]),
        .library(name: "MacCompanionKit", targets: ["MacCompanionKit"])
    ],
    targets: [
        .target(
            name: "MacCompanionKit",
            dependencies: [],
            path: "Sources/MacCompanionKit"
        ),
        .executableTarget(
            name: "MacCompanion",
            dependencies: ["MacCompanionKit"],
            path: "Sources/MacCompanion"
        ),
        .executableTarget(
            name: "protocol-test",
            dependencies: ["MacCompanionKit"],
            path: "Tests/MacCompanionTests"
        )
    ]
)

