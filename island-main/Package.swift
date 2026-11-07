// swift-tools-version: 6.0
// For Xcode / SwiftPM users. The canonical build is scripts/build.sh (plain swiftc), which CI uses.
import PackageDescription

let package = Package(
    name: "Island",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Island", targets: ["Island"])],
    targets: [
        .target(name: "IslandCore", path: "Sources/IslandCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "Island", dependencies: ["IslandCore"], path: "Sources/Island",
            swiftSettings: [.swiftLanguageMode(.v5), .define("DEBUG", .when(configuration: .debug))]
        ),
        // Dependency-free test runner: `swift run IslandCoreTests`
        .executableTarget(name: "IslandCoreTests", dependencies: ["IslandCore"], path: "Tests/IslandCoreTests",
                          swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
