// SPDX-License-Identifier: MIT
import AppKit
import Foundation
import SwiftUI

/// Where OpenNotch keeps its local data: ~/Library/Application Support/OpenNotch.
public enum AppSupport {
    public static func file(_ name: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appending(path: "OpenNotch", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: name)
    }
}

/// Runs command-line tools off the main thread.
public enum Subprocess {
    /// Runs `executable` to completion and returns its exit status and standard output.
    public static func run(_ executable: String, _ arguments: [String]) async -> (status: Int32, output: String) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(filePath: executable)
                process.arguments = arguments
                let output = Pipe()
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    // Drain before waiting, or a chatty tool fills the pipe and never exits.
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: (process.terminationStatus, String(decoding: data, as: UTF8.self)))
                } catch {
                    continuation.resume(returning: (-1, ""))
                }
            }
        }
    }
}

/// Shown instead of a feature when it can't work: unavailable on this Mac, or a permission denied.
/// Always says why and, when there is one, offers the fix.
public struct FeatureUnavailableView: View {
    let symbol: String
    let title: String
    let message: String
    let action: (label: String, perform: () -> Void)?

    public init(symbol: String, title: String, message: String, action: (label: String, perform: () -> Void)? = nil) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.action = action
    }

    public var body: some View {
        // The smallest notch drops the symbol, so the message and its fix never clip.
        ViewThatFits(in: .vertical) {
            content(symbol: true)
            content(symbol: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func content(symbol shown: Bool) -> some View {
        VStack(spacing: 6) {
            if shown { Image(systemName: symbol).font(.system(size: 22, weight: .semibold)).opacity(0.8) }
            Text(title).font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if let action {
                Button(action.label, action: action.perform)
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.15), in: Capsule())
            }
        }
    }
}

/// Liquid Glass behind a group of controls, on macOS 26 and later. Before that, and with Reduce
/// Transparency or Increase Contrast, a faint solid fill, where the controls need a steady backing.
// ponytail: the same as NotchSurface's header platter; a shared copy would need SwiftUI in NotchCore.
struct GlassPlatter<S: Shape>: View {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if #available(macOS 26, *), !reduceTransparency, contrast != .increased {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.white.opacity(0.08))
        }
    }
}

/// A time readout whose digits roll into place like an odometer whenever they change: down for
/// countdowns, up for counters. It rolls in from 0:00 when it appears. SwiftUI's numeric-text
/// transition animates each changed digit natively; Reduce Motion turns it off.
public struct RollingTime: View {
    let seconds: TimeInterval
    var tenths = false
    var countsDown = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    public init(_ seconds: TimeInterval, tenths: Bool = false, countsDown: Bool = false) {
        self.seconds = seconds
        self.tenths = tenths
        self.countsDown = countsDown
    }

    public var body: some View {
        let text = formatTime(appeared ? seconds : 0, tenths: tenths, roundingUp: countsDown)
        Text(text)
            .monospacedDigit()
            .contentTransition(.numericText(countsDown: countsDown && appeared))
            .animation(reduceMotion ? nil : .snappy(duration: tenths ? 0.12 : 0.4), value: text)
            .onAppear { appeared = true }
            .accessibilityLabel(formatTime(seconds, tenths: tenths, roundingUp: countsDown))
    }
}

/// A color reduced to sRGB components, so it can cross threads: a calendar's color, or the tint
/// taken from album art.
public struct RGB: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init?(_ color: CGColor?) {
        guard let color, let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
            let components = color.converted(to: sRGB, intent: .defaultIntent, options: nil)?.components,
            components.count >= 3
        else { return nil }
        self.init(red: components[0], green: components[1], blue: components[2])
    }

    public var color: Color { Color(red: red, green: green, blue: blue) }
}

extension View {
    /// Fades scrolling content out at its edges instead of cutting it off, so a long list reads as
    /// continuing past the fold.
    public func fadingEdges(_ axis: Axis = .vertical, length: CGFloat = 12) -> some View {
        mask {
            if axis == .vertical {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: length)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: length)
                }
            } else {
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: length)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: length)
                }
            }
        }
    }
}

extension View {
    /// Gives the notch the keyboard when `active` turns on, for a field that appears after a click
    /// elsewhere: the notch's panel only takes the keyboard by itself when a field is clicked.
    public func takesKeyboard(_ active: Bool) -> some View {
        background(KeyboardRequest(active: active).allowsHitTesting(false))
    }
}

private struct KeyboardRequest: NSViewRepresentable {
    let active: Bool

    func makeNSView(context: Context) -> RequestView { RequestView() }

    func updateNSView(_ view: RequestView, context: Context) { view.active = active }

    final class RequestView: NSView {
        var active = false {
            didSet { if active, !oldValue { request() } }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if active { request() }
        }

        /// After the update in progress, so becoming key (which changes the notch's state) isn't part of it.
        private func request() {
            Task { @MainActor [weak self] in
                guard let window = self?.window, !window.isKeyWindow else { return }
                window.makeKey()
            }
        }
    }
}

extension URL {
    /// Opens a System Settings privacy pane, e.g. "Privacy_Calendars".
    public static func privacySettings(_ pane: String) -> URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
    }
}
