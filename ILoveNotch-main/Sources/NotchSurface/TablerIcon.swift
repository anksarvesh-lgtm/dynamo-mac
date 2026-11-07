// SPDX-License-Identifier: MIT
import AppKit
import NotchCore
import SwiftUI

/// An icon from Tabler Icons (tabler.io, MIT), tinted like text. Tabler draws every icon on the same
/// 24-unit grid with the same 2-unit stroke, so side by side in the tab row they look one size, where
/// SF Symbols' shapes vary with the glyph. The files sit unchanged in the module's Icons folder.
struct TablerIcon: View {
    let name: String
    var size: CGFloat = NotchView.iconSize

    var body: some View {
        Group {
            if let image = Self.image(name) {
                Image(nsImage: image).renderingMode(.template).resizable()
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)  // the button around it says what it does
    }

    /// Each icon loads once; macOS draws SVG natively, sharp at any size.
    @MainActor private static var images: [String: NSImage] = [:]

    @MainActor static func image(_ name: String) -> NSImage? {
        if let cached = images[name] { return cached }
        guard let url = Bundle.surfaceResources.url(forResource: name, withExtension: "svg", subdirectory: "Icons"),
            let image = NSImage(contentsOf: url)
        else {
            Log.surface.error("No icon named \(name, privacy: .public)")
            return nil
        }
        image.isTemplate = true
        images[name] = image
        return image
    }
}

extension FeatureID {
    /// The tab's Tabler icon in the notch: the row, the drawer, and the tab editor. Settings keeps
    /// `symbol`, an SF Symbol, beside System Settings' own.
    var icon: String {
        switch self {
        case .media: "music"
        case .sound: "volume"
        case .shelf: "inbox"
        case .clipboard: "clipboard-list"
        case .calendar: "calendar"
        case .tasks: "list-check"
        case .notes: "notes"
        case .shortcuts: "stack-2"
        case .timer: "alarm"
        case .network: "ufo"  // beaming your data up and down
        case .mirror: "device-computer-camera"
        case .usage: "gauge"
        case .agents: "terminal-2"
        }
    }
}

extension Bundle {
    /// NotchSurface's resources (the icons). The app's Resources come first: in a packaged app,
    /// SwiftPM's `Bundle.module` can fail to find its bundle and stop the app, as NotchUsage's
    /// `openUsageResources` explains.
    static let surfaceResources: Bundle = {
        let name = "OpenNotchKit_NotchSurface.bundle"
        for case let base? in [Bundle.main.resourceURL, Bundle.main.bundleURL] {
            if let bundle = Bundle(url: base.appending(path: name)) { return bundle }
        }
        return .module
    }()
}
