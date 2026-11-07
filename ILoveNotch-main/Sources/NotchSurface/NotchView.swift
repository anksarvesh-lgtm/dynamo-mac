// SPDX-License-Identifier: MIT
import AppKit
import NotchCore
import SwiftUI

/// What the app plugs into every notch: feature views and actions the surface doesn't know about.
@MainActor
public struct NotchContent {
    /// The expanded view for a feature tab.
    public var tab: (FeatureID) -> AnyView
    /// Files dropped on the notch; returns whether they were accepted.
    public var dropFiles: ([URL]) -> Bool
    public var openSettings: () -> Void

    public init(
        tab: @escaping (FeatureID) -> AnyView,
        dropFiles: @escaping ([URL]) -> Bool,
        openSettings: @escaping () -> Void
    ) {
        self.tab = tab
        self.dropFiles = dropFiles
        self.openSettings = openSettings
    }
}

/// Horizontal and vertical scale for the squash-and-stretch animation styles.
struct Squash {
    var x: CGFloat = 1
    var y: CGFloat = 1
}

/// One display's notch. The panel around it never moves; this view animates one shape between
/// every presentation, so SwiftUI is the only animation owner.
struct NotchView: View {
    let engine: NotchEngine
    let metrics: NotchMetrics
    let preferences: NotchPreferences
    let content: NotchContent
    /// Editing the tab row, right in the drawer; nil outside edit mode.
    @State var editor: TabEditor? = nil
    /// Every app as a grid, over the open tab (`AppDrawer`).
    @State var drawer = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var dropTargeted = false
    @State private var justDropped = false
    @State private var slideForward = true
    /// The open size when a resize drag began, while one is under way.
    @State private var resizeStart: CGSize?
    /// Editing pinned the notch, so Done unpins it again.
    @State private var pinnedToEdit = false
    /// Editing opened the drawer, from the tab row's menu, so Done closes it again.
    @State private var drawerToEdit = false
    /// The open tab came from the drawer, so its content zooms in rather than sliding across.
    @State private var fromDrawer = false
    @Namespace private var selection

    var body: some View {
        let presentation = engine.state.presentation
        let resting = engine.state.restingActivity
        let size = metrics.size(for: engine.state, expanded: preferences.expandedSize)
        let outline = Self.shape(for: presentation, resting: resting != nil, on: metrics)
        ZStack(alignment: .top) {
            fill(outline, glass: showsGlass(presentation))
            if let tab = presentation.openTab {
                expanded(tab: tab, pinned: presentation.isPinned)
                    .transition(.opacity)
            } else if case .transient(let activity) = presentation {
                live(activity)
                    .transition(.opacity)
            } else if let resting {
                live(resting, ongoing: true)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(outline)  // content sliding between tabs never shows outside the notch
        .overlay {
            if contrast == .increased {
                outline.stroke(.white.opacity(0.45), lineWidth: 1)
            }
            if dropTargeted {
                outline.stroke(Color.accentColor, lineWidth: 2).shadow(color: .accentColor, radius: 6)
            }
        }
        .keyframeAnimator(initialValue: Squash(), trigger: presentation.openTab != nil) { notch, squash in
            notch.scaleEffect(x: squash.x, y: squash.y, anchor: .top)  // anchored to the screen edge
        } keyframes: { _ in
            squashKeyframes(opening: presentation.openTab != nil)
        }
        .environment(\.colorScheme, .dark)  // the notch is always black
        .gradientSymbols()
        .contentShape(outline)
        .onHover { engine.send($0 ? .pointerEntered : .pointerExited) }
        .onTapGesture { engine.send(.clicked) }
        .dropDestination(for: URL.self) { urls, _ in
            justDropped = true
            engine.send(.dropped)
            return content.dropFiles(urls)
        } isTargeted: { targeted in
            if targeted {
                justDropped = false
                engine.send(.dragEntered)
            } else if !justDropped {
                engine.send(.dragExited)
            }
            dropTargeted = targeted
        }
        // An ongoing activity's tab reaches out on the right while the rest stays over the camera.
        .offset(x: metrics.offset(for: engine.state))
        .animation(motion(for: presentation), value: presentation)
        // Only an ongoing activity coming, going, or changing kind animates. A title updating in place,
        // like a speed every second, redraws once instead of running a spring each time.
        .animation(activityMotion, value: resting.map { [$0.feature?.rawValue, $0.symbol] })
        .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.8), value: dropTargeted)
        // Closing ends editing and the drawer, so the notch opens on a tab next time.
        .onChange(of: presentation.openTab == nil) { _, closed in
            if closed {
                editor = nil
                drawer = false
                pinnedToEdit = false
                drawerToEdit = false
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("ILoveNotch")
        .accessibilityAction(named: presentation.openTab == nil ? "Open" : "Close") {
            engine.send(presentation.openTab == nil ? .clicked : .dismiss)
        }
        .padding(.top, metrics.topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// `resting` is a resting notch showing an ongoing activity, which takes a live activity's shape.
    static func shape(for presentation: NotchPresentationState, resting: Bool = false, on metrics: NotchMetrics)
        -> NotchShape
    {
        let open = presentation.openTab != nil
        guard metrics.notch != nil else {
            return NotchShape(topRadius: 0, bottomRadius: open ? 24 : Self.pillRadius, flushTop: false)
        }
        switch presentation {
        case .expanded, .pinned, .focused:
            return NotchShape(topRadius: Self.expandedTopRadius, bottomRadius: Self.expandedBottomRadius)
        case .hoverArmed, .transient: return NotchShape(topRadius: NotchMetrics.flare, bottomRadius: 13)
        case .compact where resting: return NotchShape(topRadius: NotchMetrics.flare, bottomRadius: 13)
        // Closed: rounder than the housing's own corners, so the shape stays hidden behind it.
        default: return NotchShape(topRadius: NotchMetrics.flare, bottomRadius: 10)
        }
    }

    private static let pillRadius: CGFloat = 100  // clamped to a capsule

    /// Glass only while open, with the Glass theme, on macOS 26 and later. Closed, the notch stays
    /// black to hide in the camera housing; Reduce Transparency and Increase Contrast keep it black,
    /// where text needs a solid backing most.
    private func showsGlass(_ presentation: NotchPresentationState) -> Bool {
        guard #available(macOS 26, *) else { return false }
        return presentation.openTab != nil && preferences.theme == .glass && !reduceTransparency
            && contrast != .increased
    }

    /// Black, or glass that materializes as the black fades out. The camera housing stays black over
    /// the glass, as the notch it opened from, which also draws it on a display without one.
    ///
    /// Liquid Glass shows what's behind its window only while the window is key, which the notch
    /// almost never is (it leaves the keyboard with your app); otherwise it draws a flat, opaque gray.
    /// So the desktop behind is blurred here by a view that stays live whatever the key window is,
    /// and the Liquid Glass on top samples that blur, adding its lensing at the edges, with a faint
    /// rim where Apple's catches the light.
    @ViewBuilder
    private func fill(_ outline: NotchShape, glass: Bool) -> some View {
        ZStack(alignment: .top) {
            if #available(macOS 26, *), preferences.theme == .glass {
                if glass { BehindWindowBlur().transition(.opacity) }
                GlassEffectContainer {
                    if glass {
                        Color.clear
                            .glassEffect(.clear, in: outline)
                            .glassEffectTransition(.materialize)
                    }
                }
                if glass { outline.stroke(Self.rim, lineWidth: 1.5).transition(.opacity) }
            }
            // A trace of black stays under the glass: the window server sends a click to the window
            // below wherever this one draws nothing, which closed the notch mid-click.
            outline.fill(.black).opacity(glass ? 0.01 : 1)
            if glass, metrics.notch != nil {
                Self.shape(for: .compact, on: metrics).fill(.black)
                    .frame(width: metrics.compactSize.width, height: metrics.compactSize.height)
            }
        }
    }

    /// Fades out toward the top edge, which sits against the top of the screen.
    private static let rim = LinearGradient(
        stops: [
            .init(color: .clear, location: 0), .init(color: .white.opacity(0.22), location: 0.35),
            .init(color: .white.opacity(0.08), location: 1),
        ], startPoint: .top, endPoint: .bottom)

    /// Live activities, one-shot or ongoing, come and go on their own spring.
    private var activityMotion: Animation? {
        if reduceMotion { return .easeInOut(duration: 0.12) }
        return preferences.animationStyle == .instant ? nil : .spring(response: 0.3, dampingFraction: 0.85)
    }

    /// Opening and closing in the user's chosen style. Hover only nudges and live activities keep
    /// their own spring; Reduce Motion swaps everything for a short ease.
    private func motion(for presentation: NotchPresentationState) -> Animation? {
        if reduceMotion { return .easeInOut(duration: 0.12) }
        let style = preferences.animationStyle
        switch presentation {
        case .hoverArmed: return style == .instant ? nil : .easeOut(duration: 0.12)
        case .transient: return activityMotion
        default: break
        }
        let opening = presentation.openTab != nil
        switch style {
        case .spring:
            return opening
                ? .spring(response: 0.32, dampingFraction: 0.78) : .spring(response: 0.24, dampingFraction: 0.95)
        case .jelly:
            return opening
                ? .spring(response: 0.5, dampingFraction: 0.55) : .spring(response: 0.38, dampingFraction: 0.66)
        case .pop:
            return opening
                ? .spring(response: 0.3, dampingFraction: 0.6) : .spring(response: 0.22, dampingFraction: 0.82)
        case .smooth: return .easeInOut(duration: opening ? 0.34 : 0.26)
        case .snappy: return .snappy(duration: opening ? 0.2 : 0.15)
        case .instant: return nil
        }
    }

    /// Squash-and-stretch beats layered on the size change. Jelly squashes wide, stretches down, and
    /// wobbles into place; Pop springs up from slightly smaller. Other styles hold still.
    @KeyframesBuilder<Squash>
    private func squashKeyframes(opening: Bool) -> some Keyframes<Squash> {
        let style = reduceMotion ? NotchAnimationStyle.smooth : preferences.animationStyle
        let (x, y): ([CGFloat], [CGFloat]) =
            switch (style, opening) {
            case (.jelly, true): ([1, 1.06, 0.97, 1.01], [1, 0.9, 1.04, 0.99])
            case (.jelly, false): ([1, 1.04, 0.98, 1], [1, 0.94, 1.02, 1])
            case (.pop, true): ([0.92, 1.03, 0.995, 1], [0.92, 1.03, 0.995, 1])
            case (.pop, false): ([1, 0.96, 1.01, 1], [1, 0.96, 1.01, 1])
            default: ([1, 1, 1, 1], [1, 1, 1, 1])
            }
        KeyframeTrack(\.x) {
            MoveKeyframe(x[0])
            SpringKeyframe(x[1], duration: 0.12)
            SpringKeyframe(x[2], duration: 0.16)
            SpringKeyframe(x[3], duration: 0.14)
            SpringKeyframe(1, duration: 0.2)
        }
        KeyframeTrack(\.y) {
            MoveKeyframe(y[0])
            SpringKeyframe(y[1], duration: 0.12)
            SpringKeyframe(y[2], duration: 0.16)
            SpringKeyframe(y[3], duration: 0.14)
            SpringKeyframe(1, duration: 0.2)
        }
    }

    private func expanded(tab: FeatureID, pinned: Bool) -> some View {
        VStack(spacing: 8) {
            // Liquid Glass controls, as a macOS 26 toolbar groups them: the tabs in one capsule,
            // All Apps in its own circle apart from them, and the pin with Settings. Editing keeps
            // this screen: the tabs wiggle where they are, and Done stands in for the pin and Settings.
            HStack(spacing: Self.tabSpacing) {
                if let editor {
                    EditingRow(editor: editor).background(GlassPlatter(shape: Capsule()))
                } else {
                    tabBar(selected: tab)
                }
                headerButton(
                    drawer ? "layout-grid-filled" : "layout-grid",
                    label: drawer ? "Back to \(tab.title)" : "All Apps", lit: drawer
                ) {
                    let show = !drawer
                    if editor != nil { finishEditing() }
                    showDrawer(show)
                }
                .background(GlassPlatter(shape: Circle()))
                .padding(.leading, Self.appsGap)
                Spacer(minLength: 0)
                if editor != nil {
                    DoneButton(action: finishEditing)
                } else {
                    HStack(spacing: 0) {
                        headerButton(pinned ? "pin-filled" : "pin", label: pinned ? "Unpin" : "Pin", lit: pinned) {
                            engine.send(.togglePin)
                        }
                        headerButton("settings", label: "Settings") { content.openSettings() }
                    }
                    .background(GlassPlatter(shape: Capsule()))
                }
            }
            .reportsFrame(to: editor, \.headerFrame)
            if drawer {
                AppDrawer(
                    preferences: preferences, current: tab, editor: editor, open: openFromDrawer,
                    edit: { editor == nil ? startEditing() : finishEditing() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .reportsFrame(to: editor, \.gridFrame)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.04)))
            } else {
                content.tab(tab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    // Overlay scroll bars would sit on top of charts and lists; faded edges show there's more.
                    .scrollIndicators(.never)
                    .id(tab)
                    .transition(tabTransition)
                    .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.74), value: tab)
            }
        }
        .coordinateSpace(.named(TabEditor.space))
        .overlay(alignment: .topLeading) {
            if let editor { LiftedTab(editor: editor) }
        }
        .padding(contentPadding)
        .overlay(alignment: .bottomTrailing) {
            // The grip's corner sits 10 pt in from the notch's visible corner along both edges, inside
            // its 24–26 pt rounding, in the margin beside and under the content.
            resizeGrip
                .padding(.trailing, contentPadding.trailing - 22 + 10)
                .padding(.bottom, 10)
        }
        .foregroundStyle(.white)
    }

    private static let expandedTopRadius: CGFloat = 10
    private static let expandedBottomRadius: CGFloat = 26

    /// Expanded content keeps 22 pt of black around it, measured from the visible edge: the sides of
    /// the notch outline sit inside its frame by the top radius, and the bottom corners are rounded.
    private var contentPadding: EdgeInsets {
        let side = (metrics.notch == nil ? 0 : Self.expandedTopRadius) + 22
        return EdgeInsets(top: (metrics.notch?.height ?? 0) + 10, leading: side, bottom: 22, trailing: side)
    }

    static let tabSpacing: CGFloat = 2
    private static let headerButtonWidth: CGFloat = 26
    /// More room between the tabs' glass and All Apps' than the spacing, so the two read as apart.
    private static let appsGap: CGFloat = 4
    /// Symbols that aren't the open tab or a lit button.
    private static let unlit = 0.7
    /// Every icon in the header, tabs and buttons alike, one size as in a macOS 26 toolbar: Tabler's
    /// 24-unit grid at 16 pt draws its 2-unit stroke about as heavy as SF Symbols' medium weight.
    static let iconSize: CGFloat = 16

    /// What the tabs share of the header at the smallest open size: all but the margins and the
    /// controls beside them (All Apps after its gap, then the pin and Settings side by side).
    private var tabRoom: CGFloat {
        NotchPreferences.minimumExpandedSize.width - contentPadding.leading - contentPadding.trailing
            - Self.appsGap - 3 * Self.headerButtonWidth - 3 * Self.tabSpacing
    }

    /// The widest tab that still fits `count` tabs into `room`, up to 32 pt. Tabs keep that width at
    /// every size, and each tab added makes them a little narrower instead of crowding the row.
    static func tabWidth(count: Int, room: CGFloat) -> CGFloat {
        let count = CGFloat(max(count, 1))
        return min(32, ((room - tabSpacing * (count - 1)) / count).rounded(.down))
    }

    /// Opens the app drawer over the open tab, or closes it back to that tab.
    private func showDrawer(_ show: Bool) {
        fromDrawer = true
        withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.84)) { drawer = show }
    }

    /// Opens an app from the drawer, zooming in from the grid. One that was off is turned on first and
    /// stays in the drawer, out of the row; the grid button brings the drawer back.
    private func openFromDrawer(_ feature: FeatureID) {
        if !preferences.isEnabled(feature) {
            preferences.setEnabled(feature, true)
            preferences.moveToDrawer(feature)
            // Every notch hears of it in a moment; this one needs it now to open the app.
            engine.send(.setTabs(preferences.tabs))
        }
        fromDrawer = true
        withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.84)) {
            drawer = false
            engine.send(.selectTab(feature))
        }
    }

    /// Edit mode keeps the notch open, pinning it for the while, and edits the tabs right in the
    /// drawer, which opens first when editing starts from the tab row's menu.
    private func startEditing() {
        if !engine.state.presentation.isPinned {
            engine.send(.togglePin)
            pinnedToEdit = true
        }
        if !drawer {
            drawerToEdit = true
            showDrawer(true)
        }
        withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.82)) {
            editor = TabEditor(preferences: preferences, room: tabRoom)
        }
    }

    private func finishEditing() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.82)) { editor = nil }
        if drawerToEdit { showDrawer(false) }
        drawerToEdit = false
        if pinnedToEdit, engine.state.presentation.isPinned { engine.send(.togglePin) }
        pinnedToEdit = false
    }

    /// The tab row, plus an app opened from the drawer at its end while it's open, the way the Dock
    /// shows a running app. With the drawer open, no tab is lit.
    private func tabBar(selected: FeatureID) -> some View {
        let row = preferences.rowTabs
        let tabs = row.contains(selected) ? row : row + [selected]
        let tabWidth = Self.tabWidth(count: tabs.count, room: tabRoom)
        return HStack(spacing: Self.tabSpacing) {
            ForEach(tabs, id: \.self) { tab in
                let lit = tab == selected && !drawer
                Button {
                    // Content slides the same way the selection travels.
                    slideForward = (tabs.firstIndex(of: tab) ?? 0) >= (tabs.firstIndex(of: selected) ?? 0)
                    fromDrawer = drawer
                    if drawer { showDrawer(false) }
                    engine.send(.selectTab(tab))
                } label: {
                    // One size and one outline for every tab, as Apple's tab bars keep them: the open
                    // tab stands out by its pill and brightness, never by a bigger or filled glyph.
                    TablerIcon(name: tab.icon)
                        .foregroundStyle(.white.opacity(lit ? 1 : Self.unlit))
                        .frame(width: tabWidth, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .matchedGeometryEffect(id: tab, in: selection)  // a slot the capsule can move to
                .help(tab.title)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(tab == selected ? .isSelected : [])
            }
        }
        .background {
            // One capsule travels between tabs, inside the row's glass: a bouncy spring carries it,
            // and a quick stretch-and-settle makes the move read as jelly instead of a jump.
            Capsule()
                .fill(.white.opacity(drawer ? 0 : 0.16))
                .padding(2)
                .matchedGeometryEffect(id: selected, in: selection, isSource: false)
                .keyframeAnimator(initialValue: CGSize(width: 1, height: 1), trigger: selected) { capsule, scale in
                    capsule.scaleEffect(scale)
                } keyframes: { _ in
                    let stretch: CGFloat = reduceMotion ? 1 : 1.3
                    KeyframeTrack(\.width) {
                        SpringKeyframe(stretch, duration: 0.12)
                        SpringKeyframe(reduceMotion ? 1 : 0.94, duration: 0.14)
                        SpringKeyframe(1, duration: 0.24)
                    }
                    KeyframeTrack(\.height) {
                        SpringKeyframe(2 - stretch, duration: 0.12)
                        SpringKeyframe(reduceMotion ? 1 : 1.05, duration: 0.14)
                        SpringKeyframe(1, duration: 0.24)
                    }
                }
        }
        .background(GlassPlatter(shape: Capsule()))
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.64), value: selected)
        .contextMenu {
            Button("Edit Tabs\u{2026}", action: startEditing)
        }
    }

    /// Content slides in from the side the selection moved toward, with a little scale and fade; an
    /// app opened from the drawer zooms up from its grid instead.
    private var tabTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        if fromDrawer {
            return .asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.9)), removal: .opacity)
        }
        let incoming: Edge = slideForward ? .trailing : .leading
        let outgoing: Edge = slideForward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: incoming).combined(with: .opacity).combined(with: .scale(scale: 0.96)),
            removal: .move(edge: outgoing).combined(with: .opacity))
    }

    /// The size a corner drag asks for, in whole points: the notch grows to both sides of its center
    /// and down from the screen's edge, so the width moves twice as far as the pointer.
    static func resized(_ start: CGSize, by drag: CGSize) -> CGSize {
        CGSize(width: (start.width + 2 * drag.width).rounded(), height: (start.height + drag.height).rounded())
    }

    /// `icon` is a Tabler icon's name; a button that's on (`lit`) shows its filled one.
    private func headerButton(
        _ icon: String, label: String, lit: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            TablerIcon(name: icon)
                .frame(width: Self.headerButtonWidth, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(lit ? 1 : Self.unlit))
        .help(label)
        .accessibilityLabel(label)
    }

    /// Drag the corner to resize, anywhere between the smallest and largest size. The notch grows from
    /// its center, so width moves twice as far as the pointer and the corner stays under it. Holding the
    /// button keeps the notch open even past its edge. VoiceOver steps through sizes instead.
    private var resizeGrip: some View {
        ResizeGrip(active: resizeStart != nil)
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
            .gesture(
                // Global: the grip moves with the corner, so a local translation would chase itself.
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = resizeStart ?? preferences.expandedSize
                        resizeStart = start
                        preferences.resizeExpanded(to: Self.resized(start, by: drag.translation))
                    }
                    .onEnded { _ in resizeStart = nil }
            )
            .resizeCursor()
            .help("Drag to resize")
            .accessibilityElement()
            .accessibilityLabel("Resize")
            .accessibilityValue("\(Int(preferences.expandedSize.width)) by \(Int(preferences.expandedSize.height))")
            .accessibilityAdjustableAction { direction in
                guard let next = preferences.expandedSizeStep(larger: direction == .increment) else { return }
                withAnimation(motion(for: engine.state.presentation)) { preferences.resizeExpanded(to: next) }
            }
    }

    /// A live activity, its symbol and title together: a one-shot activity in a row just under the
    /// camera housing, like a level such as the volume or the battery's charge; an ongoing one in a
    /// tab beside the housing, over the menu bar, where it can stay without covering windows. On a
    /// display without a notch, both sit inside the pill. A countdown shows the time left in place of
    /// the title, which VoiceOver still reads.
    private func live(_ activity: Activity, ongoing: Bool = false) -> some View {
        Group {
            if ongoing, metrics.notch != nil {
                HStack(spacing: 0) {
                    // Nothing under the camera housing, where it couldn't be seen.
                    Color.clear.frame(width: metrics.housing.width)
                    label(activity)
                        .padding(.leading, NotchMetrics.wingInset)
                        .padding(.trailing, NotchMetrics.wingOutset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: metrics.housing.height)
            } else if let level = activity.level {
                levelRow(activity, level: level)
            } else {
                label(activity)
                    .padding(.horizontal, NotchMetrics.rowPadding)
                    .frame(height: metrics.notch == nil ? metrics.housing.height : NotchMetrics.meterDepth)
                    .padding(.top, metrics.notch == nil ? 0 : metrics.housing.height)
            }
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }

    private func label(_ activity: Activity) -> some View {
        HStack(spacing: NotchMetrics.labelSpacing) {
            if let artwork = activity.artwork.flatMap(NSImage.init(data:)) {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: NotchMetrics.artworkSide, height: NotchMetrics.artworkSide)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .accessibilityHidden(true)
            } else {
                Image(systemName: activity.symbol)
                    .font(.system(size: 12, weight: .semibold))
            }
            Group {
                if let countdown = activity.countdown {
                    // ponytail: redraws once a second while a countdown shows; a per-minute
                    // timeline if a soak ever notices.
                    let now = Date.now
                    let left = Text(timerInterval: now...max(countdown, now), countsDown: true)
                    left.monospacedDigit().accessibilityLabel(activity.title).accessibilityValue(left)
                } else {
                    Text(activity.title)
                }
            }
            .font(.system(size: 12, weight: .medium))
            .monospacedDigit()  // numbers that change in place keep their width
            .lineLimit(1)
        }
    }

    /// Symbol, meter, and value side by side, under the camera housing (or inside the pill).
    private func levelRow(_ activity: Activity, level: Double) -> some View {
        HStack(spacing: 8) {
            Image(systemName: activity.symbol)
                .font(.system(size: 12, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 20)
            Capsule()
                .fill(.white.opacity(0.25))
                .frame(height: 5)
                .overlay(alignment: .leading) {
                    GeometryReader { track in
                        Capsule().fill(.white).frame(width: track.size.width * min(max(level, 0), 1))
                    }
                }
                .accessibilityHidden(true)
            // The value gets its room before the meter, which takes what's left: "Claude 85%", not "Claude 8…".
            Text(activity.title)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .frame(minWidth: 30, alignment: .trailing)
                .layoutPriority(1)
        }
        .padding(.horizontal, 16)
        .frame(height: metrics.notch == nil ? metrics.housing.height : NotchMetrics.meterDepth)
        .padding(.top, metrics.notch == nil ? 0 : metrics.housing.height)
    }
}

/// What's behind the notch's window, blurred and dark, and live whether or not the window is key.
private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = PassThroughEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)  // the notch's content is white
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}

    /// Clicks go to the notch's content, which SwiftUI draws over it.
    private final class PassThroughEffectView: NSVisualEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// Liquid Glass behind a group of controls, on macOS 26 and later. Before that, and with Reduce
/// Transparency or Increase Contrast, a faint solid fill, where the controls need a steady backing.
private struct GlassPlatter<S: Shape>: View {
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

/// Three diagonal strokes that run from the right edge to the bottom edge, like a window's resize
/// corner. They brighten under the pointer and while dragging.
private struct ResizeGrip: View {
    let active: Bool
    @State private var hovering = false

    var body: some View {
        Canvas { context, size in
            var strokes = Path()
            for inset in [4.0, 8.0, 12.0] {
                strokes.move(to: CGPoint(x: size.width, y: size.height - inset))
                strokes.addLine(to: CGPoint(x: size.width - inset, y: size.height))
            }
            context.stroke(strokes, with: .color(.white), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .opacity(active ? 0.95 : hovering ? 0.75 : 0.5)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityHidden(true)
    }
}

extension View {
    /// SF Symbols 7's gradient rendering, which shades each symbol from its one color like the rest
    /// of macOS 26's Liquid Glass. Drawn once, it costs nothing after.
    @ViewBuilder fileprivate func gradientSymbols() -> some View {
        if #available(macOS 26, *) {
            symbolColorRenderingMode(.gradient)
        } else {
            self
        }
    }

    /// The diagonal resize cursor, where macOS has one (15 and later).
    @ViewBuilder fileprivate func resizeCursor() -> some View {
        if #available(macOS 15, *) {
            pointerStyle(.frameResize(position: .bottomTrailing))
        } else {
            self
        }
    }
}
