// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchIsland",
    platforms: [.macOS(.v13)],
    products: [
        // Loaded by /usr/bin/perl, not by the app: see Sources/MediaRemoteAdapter/adapter.m.
        .library(name: "MediaRemoteAdapter", type: .dynamic, targets: ["MediaRemoteAdapter"]),
    ],
    targets: [
        .target(
            name: "MediaRemoteAdapter",
            path: "Sources/MediaRemoteAdapter",
            cSettings: [.unsafeFlags(["-fobjc-arc"])],
            linkerSettings: [.linkedFramework("Foundation")]
        ),
        // Embeds an Info.plist into the executable (see Sources/NotchIslandInfoPlist/info.c).
        .target(
            name: "NotchIslandInfoPlist",
            path: "Sources/NotchIslandInfoPlist"
        ),
        .executableTarget(
            name: "NotchIsland",
            dependencies: ["NotchIslandInfoPlist"],
            path: "Sources/NotchIsland",
            linkerSettings: [
                .linkedFramework("EventKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("IOKit"),
                .linkedFramework("UniformTypeIdentifiers"),
            ]
        ),
    ]
)
