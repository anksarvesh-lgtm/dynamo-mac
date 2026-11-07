import AppKit
import IslandCore
import SwiftUI

// MARK: Environment

private struct IslandNamespaceKey: EnvironmentKey { static let defaultValue: Namespace.ID? = nil }
private struct IslandCommandsKey: EnvironmentKey { static let defaultValue: IslandCommandSink = IslandCommandSink { _ in } }
private struct IslandReduceMotionKey: EnvironmentKey { static let defaultValue = false }
private struct IslandContentActiveKey: EnvironmentKey { static let defaultValue = true }

/// Lightweight value wrapper so views can emit commands without knowing the router type.
struct IslandCommandSink: Sendable {
    let send: @MainActor @Sendable (IslandCommand) -> Void
    init(_ send: @escaping @MainActor @Sendable (IslandCommand) -> Void) { self.send = send }
    @MainActor func callAsFunction(_ c: IslandCommand) { send(c) }
}

extension EnvironmentValues {
    var islandNamespace: Namespace.ID? {
        get { self[IslandNamespaceKey.self] }
        set { self[IslandNamespaceKey.self] = newValue }
    }
    var islandCommands: IslandCommandSink {
        get { self[IslandCommandsKey.self] }
        set { self[IslandCommandsKey.self] = newValue }
    }
    /// False while a layer is mounted but hidden; per-second clocks inside it pause.
    var islandContentActive: Bool {
        get { self[IslandContentActiveKey.self] }
        set { self[IslandContentActiveKey.self] = newValue }
    }
    var islandReduceMotion: Bool {
        get { self[IslandReduceMotionKey.self] }
        set { self[IslandReduceMotionKey.self] = newValue }
    }
}

extension View {
    /// matchedGeometryEffect that is a no-op when no namespace is available (e.g. previews, debug panel).
    @ViewBuilder
    func islandMatched(_ id: String, in ns: Namespace.ID?, isSource: Bool = true) -> some View {
        if let ns { matchedGeometryEffect(id: id, in: ns, isSource: isSource) } else { self }
    }
}

// MARK: Palette

enum IslandPalette {
    static let timer = Color(red: 1.0, green: 0.62, blue: 0.04)
    static let download = Color(red: 0.25, green: 0.6, blue: 1.0)
    static let recording = Color(red: 1.0, green: 0.42, blue: 0.0)
    static let batteryGood = Color(red: 0.2, green: 0.85, blue: 0.35)
    static let batteryLow = Color(red: 1.0, green: 0.27, blue: 0.23)
    static let network = Color(red: 0.35, green: 0.8, blue: 0.85)
    static let secondaryText = Color.white.opacity(0.62)

    static func hex(_ hex: String?) -> Color? {
        guard var s = hex?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

// MARK: Controls

struct IslandIconButton: View {
    var symbol: String
    var size: CGFloat = 15
    var label: String
    var enabled = true
    var prominent = false
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(enabled ? 1 : 0.3))
                .frame(width: size * 2.3, height: size * 2.3)
                .background(Circle().fill(.white.opacity(prominent ? 0.18 : (hovering && enabled ? 0.12 : 0))))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
        .help(label)
    }
}

struct IslandPillButton: View {
    var title: String
    var symbol: String?
    var tint: Color = .white
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(tint.opacity(hovering ? 0.26 : 0.16)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct ProgressRing: View {
    var fraction: Double
    var tint: Color
    var lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct LinearProgress: View {
    var fraction: Double?
    var tint: Color
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.16))
                if let fraction {
                    Capsule().fill(tint).frame(width: max(height, geo.size.width * min(1, max(0, fraction))))
                }
            }
        }
        .frame(height: height)
    }
}

/// Generic icon + title + subtitle expanded layout used by short-lived events.
struct EventExpandedView: View {
    var symbol: String
    var tint: Color
    var title: String
    var subtitle: String?
    var ns: Namespace.ID?
    var matchID: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .islandMatched(matchID, in: ns)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(IslandPalette.secondaryText).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

enum Formatters {
    static func bytes(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }
    static func speed(_ bps: Double) -> String { bytes(Int64(bps)) + "/s" }
    static let time: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()
}

/// Seconds between clock ticks: 1 s while visible, effectively paused while hidden.
func clockInterval(active: Bool, running: Bool = true) -> TimeInterval { active && running ? 1 : 3600 }
