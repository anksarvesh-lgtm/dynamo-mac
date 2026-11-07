// SPDX-License-Identifier: MIT
import AppKit
import NotchCore

/// "Show in Notch": a short message from Shortcuts, a script, or another app, shown as a live
/// activity. Everything in it comes from outside, so it's only ever displayed: the text is cleaned
/// up and shortened, the symbol must be a real SF Symbol, and nothing in it is opened or run.
public enum ShowInNotch {
    public static let scheme = "ilovenotch"
    public static let defaultSymbol = "bell.fill"
    /// Longer than the notch can show; the rest would only be room for abuse.
    static let maximumLength = 80
    static let seconds: ClosedRange<Double> = 1...30

    /// The message as a live activity, or nil when there's nothing to show.
    public static func activity(title: String, symbol: String?, seconds: Double?) -> Activity? {
        // Line breaks and other controls become spaces, and bidi overrides go, so text can't
        // disguise itself; emoji and other joined characters stay whole.
        var scalars = String.UnicodeScalarView()
        for scalar in title.unicodeScalars where !scalar.properties.isBidiControl {
            scalars.append(scalar.properties.generalCategory == .control ? " " : scalar)
        }
        let text = String(scalars).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !text.isEmpty else { return nil }
        let known = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil ? $0 : nil }
        let requested = seconds.flatMap { $0.isFinite ? $0 : nil } ?? 4
        let duration = min(max(requested, Self.seconds.lowerBound), Self.seconds.upperBound)
        return Activity(
            feature: nil, symbol: known ?? defaultSymbol, title: String(text.prefix(maximumLength)),
            duration: .milliseconds(Int(duration * 1000)))
    }

    /// `ilovenotch://show?title=Build%20done&symbol=hammer.fill&seconds=5`, or nil for any other
    /// link.
    public static func activity(from url: URL) -> Activity? {
        guard url.scheme?.lowercased() == scheme, url.host()?.lowercased() == "show",
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        let seconds = value("seconds").flatMap(Double.init)
        return activity(title: value("title") ?? "", symbol: value("symbol"), seconds: seconds)
    }
}
