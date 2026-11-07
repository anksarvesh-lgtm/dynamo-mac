// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacLinkTelephony",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MacLinkTelephony",
            type: .static,
            targets: ["MacLinkTelephony"]
        ),
        .executable(
            name: "telephony-test",
            targets: ["telephony-test"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MacLinkTelephony",
            dependencies: [],
            path: "Sources/MacLinkTelephony"
        ),
        .executableTarget(
            name: "telephony-test",
            dependencies: ["MacLinkTelephony"],
            path: "Sources/telephony-test"
        ),
    ]
)
