// swift-tools-version: 6.2
// SPDX-License-Identifier: MIT
import PackageDescription

// Every target builds in the Swift 6 language mode: complete strict-concurrency checking. OpenNotch's
// own code treats warnings as errors; the vendored OpenUsage code keeps upstream's warnings as
// warnings, so it can stay close to upstream.
let strict: [SwiftSetting] = [.treatAllWarnings(as: .error)]

let package = Package(
    name: "OpenNotchKit",
    platforms: [.macOS("14.6")],
    products: [
        .library(name: "NotchCore", targets: ["NotchCore"]),
        .library(name: "NotchSurface", targets: ["NotchSurface"]),
        .library(name: "NotchFeatures", targets: ["NotchFeatures"]),
        .library(name: "NotchUsage", targets: ["NotchUsage"]),
        .library(name: "NotchTransfer", targets: ["NotchTransfer"]),
        .library(name: "NotchMixer", targets: ["NotchMixer"]),
    ],
    targets: [
        // State machine, feature lifecycle, diagnostics. No AppKit, so it tests anywhere.
        .target(name: "NotchCore", swiftSettings: strict),
        // Panel, SwiftUI surface, and notch geometry.
        .target(
            name: "NotchSurface", dependencies: ["NotchCore"],
            // The notch's own icons from Tabler Icons (tabler.io; MIT, see THIRD_PARTY_NOTICES.md).
            resources: [.copy("Resources/Icons")], swiftSettings: strict),
        // Feature modules: each one a NotchFeature plus its views.
        .target(name: "NotchFeatures", dependencies: ["NotchCore"], swiftSettings: strict),
        // The GitHub build's developer tabs: AI Usage, OpenUsage's providers (MIT, in OpenUsage/) with
        // OpenNotch's tab, and Agents, Claude Code and Codex hooks (in Agents/).
        .target(
            name: "NotchUsage", dependencies: ["NotchCore", "NotchFeatures"],
            resources: [
                .copy("Resources/pricing_litellm_snapshot.json"),
                .copy("Resources/pricing_models_dev_snapshot.json"),
                .copy("Resources/pricing_supplement.json"),
                // Provider marks from theSVG (thesvg.org; CC0 or MIT, see THIRD_PARTY_NOTICES.md).
                .copy("Resources/Logos"),
            ]),
        // The GitHub build's Android sharing: Quick Share over the local network, on Apple's own
        // frameworks only (docs/filesharing.md).
        .target(name: "NotchTransfer", dependencies: ["NotchCore", "NotchFeatures"], swiftSettings: strict),
        // The GitHub build's per-app volume, in the Media tab: Core Audio process taps, and a private
        // call that tells which app a helper process (Safari's WebKit, say) plays for.
        .target(name: "NotchMixer", dependencies: ["NotchCore", "NotchFeatures"], swiftSettings: strict),
        .testTarget(name: "NotchCoreTests", dependencies: ["NotchCore"], swiftSettings: strict),
        .testTarget(name: "NotchSurfaceTests", dependencies: ["NotchSurface"], swiftSettings: strict),
        .testTarget(name: "NotchFeaturesTests", dependencies: ["NotchFeatures"], swiftSettings: strict),
        .testTarget(name: "NotchUsageTests", dependencies: ["NotchUsage"], swiftSettings: strict),
        .testTarget(name: "NotchTransferTests", dependencies: ["NotchTransfer"], swiftSettings: strict),
        .testTarget(name: "NotchMixerTests", dependencies: ["NotchMixer"], swiftSettings: strict),
        // OpenUsage's own tests (MIT) for the providers, mappers, and pricing we adapted, on its fixtures.
        .testTarget(name: "OpenUsageTests", dependencies: ["NotchUsage"]),
        // XCTest metrics (clock, CPU, memory, signposts) for the core's hot paths.
        .testTarget(name: "PerformanceTests", dependencies: ["NotchCore"], swiftSettings: strict),
    ]
)
