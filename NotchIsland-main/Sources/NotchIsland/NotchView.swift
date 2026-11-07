import SwiftUI
import Combine
import UniformTypeIdentifiers

/// The whole UI is one black surface flush with the top of the screen: flat top, rounded bottom.
/// It grows from the notch into the hover readout, a live-activity HUD, the banner, the shade or
/// the launcher, so the notch and whatever drops down always read as a single thing.
struct NotchView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var updater = Updater.shared
    @State private var now = Date()
    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var geo: NotchGeometry { .current }

    /// A window's worth of shadow: soft, mostly below the surface, a few points at the sides. None
    /// while the island is only the notch and its ears, which sit inside the menu bar.
    private func shadowOpacity(_ layout: IslandLayout) -> Double {
        guard settings.islandShadow else { return 0 }
        switch layout.mode {
        case .collapsed, .compact: return 0
        default: return 0.3
        }
    }

    var body: some View {
        surface
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onReceive(clock) { now = $0 }
    }

    private var surface: some View {
        let g = geo
        let layout = state.layout

        return VStack(spacing: 0) {
            content(layout, g)
        }
        .frame(width: layout.surfaceWidth(g))
        .background(Color.black)
        .clipShape(IslandSurfaceShape(radius: layout.cornerRadius))
        .shadow(color: .black.opacity(shadowOpacity(layout)), radius: 8, y: 4)
        .contentShape(Rectangle())
        .onHover { state.setHovering($0) }
        .onTapGesture {
            switch layout.mode {
            case .banner: state.openBanner()
            case .activity:
                if state.activity?.kind == .update {
                    state.activities.dismiss(id: "update")
                    SettingsWindowController.shared.show(tab: "updates")
                } else {
                    state.activities.dismissByUser()
                }
            case .collapsed, .compact, .expanded: state.toggleShade()
            case .shade, .launcher: break   // inner controls handle taps
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $state.isDragTargeted) { providers in
            guard settings.shelfEnabled else { return false }
            ShelfStore.urls(from: providers) { urls in
                state.shelf.add(urls)
                if !urls.isEmpty { state.openShade() }
            }
            return true
        }
        .animation(Motion.spring, value: layout)
    }

    private func notchClearance(_ g: NotchGeometry) -> some View {
        Color.clear.frame(height: g.notchHeight)
    }

    @ViewBuilder
    private func content(_ layout: IslandLayout, _ g: NotchGeometry) -> some View {
        switch layout.mode {
        case .collapsed:
            Color.clear.frame(width: g.notchWidth, height: g.notchHeight)

        case .compact:
            ZStack {
                Color.clear.frame(height: g.notchHeight)
                if layout.compactEars {
                    CompactEars(state: state, timer: state.timer, status: state.status,
                                notchWidth: g.notchWidth, height: g.notchHeight)
                }
            }

        case .activity:
            VStack(spacing: 0) {
                notchClearance(g)
                if let a = state.activity {
                    ActivityHUD(activity: a).id(a.id).transition(.opacity)
                }
            }

        case .banner:
            VStack(spacing: 0) {
                notchClearance(g)
                if let note = state.banner {
                    NotificationBannerView(note: note,
                                           onOpen: { state.openBanner() },
                                           onDismiss: { state.dismissBanner() })
                        .id(note.id)
                        .transition(.opacity)
                }
            }

        case .expanded:
            VStack(spacing: 0) {
                notchClearance(g)
                expandedContent.transition(.opacity)
            }

        case .shade:
            VStack(spacing: 0) {
                notchClearance(g)
                ShadeContent(state: state).transition(.opacity)
            }

        case .launcher:
            VStack(spacing: 0) {
                notchClearance(g)
                LauncherView(state: state, engine: state.launcher).transition(.opacity)
            }
        }
    }

    // MARK: Hover (expanded) content

    private var expandedContent: some View {
        VStack(spacing: UI.stack) {
            if state.isDragTargeted {
                dropHint
            } else {
                statusRow
                if settings.timerEnabled, state.timerActive {
                    TimerCard(engine: state.timer)
                }
                if settings.calendarEnabled, state.calendar.next != nil {
                    CalendarRow(calendar: state.calendar)
                }
                if let media = state.media {
                    MediaCard(media: media, controller: state.mediaController)
                }
                if let note = state.footerNotification {
                    recentRow(note)
                } else if let hint = state.hint {
                    hintRow(hint)
                } else if let release = updater.available {
                    updateRow(release)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private var dropHint: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: "tray.and.arrow.down.fill", tint: Theme.accent, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Drop to add to the Shelf").font(UI.title())
                Text("Park files here, drag them out or AirDrop them later")
                    .font(UI.body(10.5)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .islandCard()
        .overlay(RoundedRectangle(cornerRadius: UI.cardRadius, style: .continuous)
            .strokeBorder(Theme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
    }

    /// Clock and date on the left; status chips, battery and the notification bell on the right.
    private var statusRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(now, format: .dateTime.hour().minute())
                    .font(UI.numeral(20)).monospacedDigit()
                Text(now, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                    .font(UI.body(10.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            if settings.indicatorsEnabled {
                IndicatorStrip(status: state.status, caffeine: state.caffeine)
            }
            BatteryBadge()
            notificationsButton
        }
        .padding(.horizontal, 4)
    }

    private var notificationsButton: some View {
        let count = state.groups.reduce(0) { $0 + $1.notes.count }
        return IconButton(symbol: "bell.fill", size: 30, help: "Notifications") { state.toggleShade() }
            .overlay(alignment: .topTrailing) {
                if count > 0 {
                    Text(count > 99 ? "99+" : "\(count)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 15, minHeight: 15)
                        .background(Theme.accent, in: Capsule())
                        .offset(x: 4, y: -3)
                }
            }
    }

    private func recentRow(_ note: NotchNotification) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: note.icon).resizable().frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(note.appName.uppercased()).font(UI.eyebrow).tracking(0.5).foregroundStyle(.secondary)
                Text(note.headline + (note.body.isEmpty ? "" : " · " + note.body))
                    .font(UI.body(11))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(NotificationBannerView.relative(note.date))
                .font(UI.caption())
                .foregroundStyle(.secondary)
            IconButton(symbol: "xmark", size: 20, help: "Clear") { state.clearLatest() }
        }
        .islandCard(padding: 10)
        .contentShape(Rectangle())
        .onTapGesture { state.open(note) }
    }

    /// A problem line; when the hint names a System Settings pane, the whole row opens it.
    private func hintRow(_ hint: IslandHint) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(UI.warning)
            Text(hint.text).font(UI.body(10.5)).foregroundStyle(.secondary).lineLimit(2)
            Spacer(minLength: 0)
            if hint.settingsPane != nil {
                Text("Open Settings")
                    .font(UI.caption())
                    .foregroundStyle(Theme.accent)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture { if let pane = hint.settingsPane { PrivacyPane.open(pane) } }
        .help(hint.settingsPane == nil ? hint.text : "\(hint.text) Click to open System Settings.")
    }

    /// A newer release is out; the row opens Settings ▸ Updates with the notes and the Update button.
    private func updateRow(_ release: AppRelease) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(UI.info)
            Text("NotchIsland \(release.version) is available").font(UI.body(10.5)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
            Text("What's new")
                .font(UI.caption())
                .foregroundStyle(Theme.accent)
                .fixedSize()
        }
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture { SettingsWindowController.shared.show(tab: "updates") }
        .help("Open Settings ▸ Updates")
    }
}

// MARK: - Compact ears

/// What sits beside the notch when collapsed: artwork / timer ring / an indicator on the left,
/// level meter / timer countdown / mic-camera-focus marks on the right.
struct CompactEars: View {
    @ObservedObject var state: IslandState
    @ObservedObject var timer: TimerEngine
    @ObservedObject var status: SystemStatus
    let notchWidth: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            leftEar.frame(width: IslandLayout.earWidth, height: height)
            Spacer().frame(width: notchWidth)
            rightEar.frame(width: IslandLayout.earWidth, height: height)
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder private var leftEar: some View {
        if let media = state.media {
            ArtworkView(image: media.artwork, size: 18, radius: 4)
        } else if let sticky = state.stickyActivity {
            if let image = sticky.image {
                Image(nsImage: image).resizable().frame(width: 18, height: 18)
            } else {
                earGlyph(sticky.symbol, sticky.tint)
            }
        } else if timer.isActive {
            TimerRing(progress: timer.progress, size: 16, lineWidth: 2.5)
        } else if status.focusName != nil {
            earGlyph("moon.fill", UI.focus)
        } else if status.micInUse {
            earGlyph("mic.fill", UI.mic)
        } else if status.cameraInUse {
            earGlyph("video.fill", UI.camera)
        }
    }

    @ViewBuilder private var rightEar: some View {
        if let media = state.media, media.isPlaying {
            LevelMeter(playing: true)
        } else if let sticky = state.stickyActivity {
            ActivityRing(progress: sticky.progress, tint: sticky.tint, size: 16)
                .help(sticky.title + (sticky.subtitle.isEmpty ? "" : " · " + sticky.subtitle))
        } else if timer.isActive, state.media == nil {
            Text(timer.display)
                .font(UI.numeral(10))
                .monospacedDigit()
        } else {
            HStack(spacing: 4) {
                if status.micInUse { Circle().fill(UI.mic).frame(width: 7, height: 7) }
                if status.cameraInUse { Circle().fill(UI.camera).frame(width: 7, height: 7) }
                if status.focusName != nil, state.media != nil || status.micInUse || status.cameraInUse {
                    Image(systemName: "moon.fill").font(.system(size: 8, weight: .semibold)).foregroundStyle(UI.focus)
                }
            }
        }
    }

    private func earGlyph(_ symbol: String, _ tint: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
    }
}

/// Mic / Camera / Focus / Awake chips for the hover row. Full labels when there is room for them,
/// icon-only when three or more are lit, so a label like "Do Not Disturb" is never cut short.
struct IndicatorStrip: View {
    @ObservedObject var status: SystemStatus
    @ObservedObject var caffeine: Caffeine

    private struct Indicator: Identifiable {
        let id: String      // symbol
        let text: String
        let tint: Color
    }

    private var indicators: [Indicator] {
        var out: [Indicator] = []
        if status.micInUse { out.append(Indicator(id: "mic.fill", text: "Mic", tint: UI.mic)) }
        if status.cameraInUse { out.append(Indicator(id: "video.fill", text: "Camera", tint: UI.camera)) }
        if let f = status.focusName { out.append(Indicator(id: "moon.fill", text: f, tint: UI.focus)) }
        if caffeine.isOn { out.append(Indicator(id: "cup.and.saucer.fill", text: "Awake", tint: Theme.accent)) }
        return out
    }

    var body: some View {
        let items = indicators
        HStack(spacing: 5) {
            ForEach(items) { item in
                StatusPill(symbol: item.id, text: item.text, tint: item.tint, iconOnly: items.count > 2)
            }
        }
    }
}

/// The black surface: flush with the top of the screen (flat top), rounded bottom corners, one
/// uniform width top-to-bottom.
struct IslandSurfaceShape: Shape {
    var radius: CGFloat
    var animatableData: CGFloat {
        get { radius } set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(radius, min(rect.width, rect.height) / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

struct BatteryBadge: View {
    var body: some View {
        let info = Battery.read()
        let low = info.percent <= 20 && !info.onAC
        HStack(spacing: 4) {
            Image(systemName: Self.symbol(percent: info.percent, onAC: info.onAC))
                .font(.system(size: 11, weight: .semibold))
            Text("\(info.percent)%").font(.system(size: 11, weight: .medium)).monospacedDigit()
        }
        .foregroundStyle(low ? UI.danger : .white)
        .help(info.onAC ? "Charging" : "On battery")
    }

    static func symbol(percent: Int, onAC: Bool) -> String {
        if onAC { return "battery.100percent.bolt" }
        switch percent {
        case ..<10: return "battery.0percent"
        case ..<35: return "battery.25percent"
        case ..<60: return "battery.50percent"
        case ..<85: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
