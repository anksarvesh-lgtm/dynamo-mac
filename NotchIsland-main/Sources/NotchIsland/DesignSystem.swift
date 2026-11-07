import AppKit
import SwiftUI

/// The island's shared visual language. Every card, icon, button and tint drawn on the black
/// surface comes from here, so the notch, the HUD, the hover readout, the shade and the launcher
/// read as one product instead of five.
enum UI {
    // Radii
    static let cardRadius: CGFloat = 18
    static let tileRadius: CGFloat = 16

    // Spacing
    static let cardPadding: CGFloat = 14
    static let stack: CGFloat = 10          // between cards

    // Fills on black
    static var cardFill: Color { .white.opacity(AppSettings.shared.translucentShade ? 0.11 : 0.07) }
    static let cardStroke = Color.white.opacity(0.07)
    static let controlFill = Color.white.opacity(0.12)
    static let track = Color.white.opacity(0.16)
    static let divider = Color.white.opacity(0.09)

    // Semantic tints — match the macOS menu-bar indicators where one exists.
    static let focus = Color(red: 0.71, green: 0.57, blue: 1.00)
    static let mic = Color(red: 1.00, green: 0.63, blue: 0.24)
    static let camera = Color(red: 0.33, green: 0.86, blue: 0.47)
    static let success = Color(red: 0.36, green: 0.86, blue: 0.48)
    static let warning = Color(red: 1.00, green: 0.80, blue: 0.27)
    static let danger = Color(red: 1.00, green: 0.40, blue: 0.38)
    static let info = Color(red: 0.42, green: 0.70, blue: 1.00)
    static let muted = Color.white.opacity(0.55)

    // Type scale
    static func title(_ size: CGFloat = 13) -> Font { .system(size: size, weight: .semibold) }
    static func body(_ size: CGFloat = 11) -> Font { .system(size: size) }
    static func caption(_ size: CGFloat = 9.5) -> Font { .system(size: size, weight: .medium) }
    static func numeral(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
    static let eyebrow: Font = .system(size: 9.5, weight: .semibold)
}

// MARK: - Surfaces

/// The one card style: soft fill, hairline edge, continuous corners.
struct IslandCard: ViewModifier {
    var padding: CGFloat = UI.cardPadding

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(UI.cardFill, in: RoundedRectangle(cornerRadius: UI.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: UI.cardRadius, style: .continuous)
                .strokeBorder(UI.cardStroke, lineWidth: 1))
    }
}

extension View {
    func islandCard(padding: CGFloat = UI.cardPadding) -> some View { modifier(IslandCard(padding: padding)) }
}

struct HairlineDivider: View {
    var body: some View { Rectangle().fill(UI.divider).frame(height: 1) }
}

// MARK: - Icons

/// A glyph on a tinted rounded square: the one way an icon leads a row (HUD, launcher, timer,
/// calendar, empty states).
struct IconBadge: View {
    let symbol: String
    var tint: Color = .white
    var size: CGFloat = 32
    var filled = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(filled ? Theme.on(tint) : tint)
            .frame(width: size, height: size)
            .background(filled ? tint : tint.opacity(0.16),
                        in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

/// Round icon button: header actions and close marks.
struct IconButton: View {
    let symbol: String
    var size: CGFloat = 28
    var help = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(UI.controlFill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Capsule text button. `prominent` fills it with the accent colour.
struct PillButton: View {
    let title: String
    var symbol: String? = nil
    var prominent = false
    var small = false
    var help = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: small ? 9 : 10, weight: .bold))
                }
                Text(title)
                    .font(.system(size: small ? 10.5 : 11.5, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(prominent ? Theme.onAccent : .white)
            .padding(.horizontal, small ? 10 : 12)
            .frame(height: small ? 24 : 28)
            .background(prominent ? Theme.accent : UI.controlFill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Keyboard hint (⌥ Space, ↩).
struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(UI.controlFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Colour-coded status chip: Mic, Camera, Focus, Awake. Text never truncates; it goes icon-only
/// instead when the row asks for it.
struct StatusPill: View {
    let symbol: String
    let text: String
    let tint: Color
    var iconOnly = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            if !iconOnly {
                Text(text).font(.system(size: 9.5, weight: .semibold)).lineLimit(1).fixedSize()
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, iconOnly ? 7 : 8)
        .frame(height: 22)
        .background(tint.opacity(0.16), in: Capsule())
        .help(text)
    }
}

/// Section label inside a list card: 16 pt mark, UPPERCASE title, optional count, trailing controls.
struct Eyebrow<Trailing: View>: View {
    enum Mark { case symbol(String), image(NSImage) }

    let mark: Mark
    let title: String
    var count: Int? = nil
    @ViewBuilder let trailing: () -> Trailing

    init(symbol: String, _ title: String, count: Int? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.mark = .symbol(symbol); self.title = title; self.count = count; self.trailing = trailing
    }
    init(image: NSImage, _ title: String, count: Int? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.mark = .image(image); self.title = title; self.count = count; self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 7) {
            switch mark {
            case .symbol(let s):
                Image(systemName: s)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
            case .image(let i):
                Image(nsImage: i).resizable().frame(width: 16, height: 16)
            }
            Text(title.uppercased())
                .font(UI.eyebrow)
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let count, count > 1 {
                Text("\(count)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(UI.controlFill, in: Capsule())
            }
            Spacer(minLength: 6)
            HStack(spacing: 6) { trailing() }
        }
    }
}

extension Eyebrow where Trailing == EmptyView {
    init(symbol: String, _ title: String, count: Int? = nil) {
        self.init(symbol: symbol, title, count: count) { EmptyView() }
    }
}

// MARK: - Controls

/// Horizontal progress track shared by the scrubber, the volume slider and HUD bars.
struct TrackBar: View {
    let fraction: Double
    var tint: Color = Theme.accent
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(UI.track)
                Capsule().fill(tint).frame(width: geo.size.width * CGFloat(max(0, min(1, fraction))))
            }
        }
        .frame(height: height)
    }
}

/// Quick-toggle tile: glyph over a label that may wrap to two lines ("Do Not / Disturb"), so no
/// label is ever squeezed or clipped. On = accent fill with a contrasting glyph.
struct ToggleTile: View {
    let symbol: String
    let label: String
    let on: Bool
    var help = ""
    let action: () -> Void

    var body: some View {
        Button(action: { Feedback.tap(); action() }) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(height: 20)
                Text(label)
                    .font(.system(size: 9.5, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(on ? Theme.onAccent : .white)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .background(on ? Theme.accent : UI.cardFill,
                        in: RoundedRectangle(cornerRadius: UI.tileRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: UI.tileRadius, style: .continuous)
                .strokeBorder(on ? Color.clear : UI.cardStroke, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: UI.tileRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
