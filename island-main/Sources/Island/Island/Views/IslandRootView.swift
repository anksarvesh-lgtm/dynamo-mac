import IslandCore
import SwiftUI

/// The Island's SwiftUI content. The surface itself — outline, glass, clip and the open/close
/// morph — is `IslandSurfaceView` (Core Animation), so this view is laid out at its final size and
/// never re-laid-out frame by frame while the Island springs.
struct IslandRootView: View {
    let model: IslandViewModel
    let search: SearchViewModel

    var body: some View {
        let metrics = model.metrics
        let mode = model.mode
        let canvas = metrics.windowSize

        content(metrics: metrics, size: model.islandSize)
            .offset(x: mode == .compact ? model.horizontalOffset : 0)
            .frame(width: canvas.width, height: canvas.height, alignment: .top)
            // Clicks only reach this window inside the Island (the rest is click-through).
            .contentShape(Rectangle())
            .onTapGesture { model.click() }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Island")
            .accessibilityAddTraits(mode == .compact ? .isButton : [])
            .accessibilityAction(named: mode == .expanded ? "Collapse" : "Expand") {
                mode == .expanded ? model.collapse() : model.expand()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // No shared matched-geometry namespace: compact and expanded are both mounted and crossfade,
            // and duplicate matched IDs in mounted views would misplace content.
            .environment(\.islandReduceMotion, model.reduceMotion)
            .environment(\.airPodsRevealed, model.airPods.map { $0.phase == .idle || $0.isRevealed } ?? true)
            .environment(\.islandCommands, IslandCommandSink { [weak model] c in model?.commands.perform(c) })
            .environment(\.colorScheme, .dark)
            .animation(IslandAnimation.contentChange(reduceMotion: model.reduceMotion), value: model.manager.primary?.id)
            .animation(IslandAnimation.contentChange(reduceMotion: model.reduceMotion), value: model.manager.secondaries.map(\.id))
    }

    /// Compact and expanded stay mounted and crossfade, so opening never builds views mid-animation
    /// (that's what dropped frames). Hidden layers don't take clicks, aren't announced by VoiceOver,
    /// and their once-per-second clocks pause (`islandContentActive`).
    @ViewBuilder
    private func content(metrics: IslandMetrics, size: CGSize) -> some View {
        let mode = model.mode
        let reduce = model.reduceMotion
        ZStack(alignment: .top) {
            if let primary = model.primary {
                let compactShown = mode == .compact
                CompactLayout(activity: primary, minimals: Array(model.secondaries.prefix(IslandMetrics.maxMinimals)),
                              metrics: metrics, style: model.compactStyle, showsTitle: model.settings.compactShowsTitle)
                    .offset(x: metrics.horizontalOffset(mode: .compact, compact: model.compactStyle,
                                                        minimals: min(model.secondaries.count, IslandMetrics.maxMinimals)))
                    .id("compact-\(primary.id)")
                    .environment(\.islandContentActive, compactShown)
                    .layer(shown: compactShown, delay: 0.1, reduceMotion: reduce)
            }
            ExpandedLayout(model: model, metrics: metrics)
                .frame(width: metrics.expandedWidth)
                .environment(\.islandContentActive, mode == .expanded)
                .layer(shown: mode == .expanded, delay: 0.1, reduceMotion: reduce)
            if mode == .search {
                SearchSurface(model: search, metrics: metrics)
                    .frame(width: metrics.searchWidth, height: size.height, alignment: .top)
                    .transition(IslandAnimation.contentTransition(reduceMotion: reduce))
            }
        }
    }
}

private extension View {
    /// Crossfade a mounted layer: leaving is quick, arriving waits for the glass to mostly open.
    func layer(shown: Bool, delay: Double, reduceMotion: Bool) -> some View {
        self
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : 0.97, anchor: .top)
            .allowsHitTesting(shown)
            .accessibilityHidden(!shown)
            .animation(shown ? .easeOut(duration: reduceMotion ? 0.15 : 0.24).delay(reduceMotion ? 0 : delay)
                             : .easeIn(duration: reduceMotion ? 0.1 : 0.08), value: shown)
    }
}

/// `[ leading ]  notch  [ trailing · minimals ]`
struct CompactLayout: View {
    let activity: Activity
    let minimals: [Activity]
    let metrics: IslandMetrics
    let style: CompactStyle
    var showsTitle = false
    @Environment(\.islandNamespace) private var ns

    var body: some View {
        let wings = metrics.compactWings(style, minimals: minimals.count)
        let pad = max(8, metrics.compactHeight * 0.28)
        HStack(spacing: 0) {
            CompactLeadingView(activity: activity, showsTitle: showsTitle)
                .frame(width: wings.leading - pad, alignment: .leading)
                .padding(.leading, pad)
            Color.clear.frame(width: metrics.notchSize.width)
            HStack(spacing: 0) {
                CompactTrailingView(activity: activity)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                if !minimals.isEmpty {
                    Capsule().fill(.white.opacity(0.18)).frame(width: 1, height: metrics.compactHeight * 0.45)
                        .padding(.horizontal, 4)
                    ForEach(minimals) { m in
                        MinimalView(activity: m)
                            .frame(width: 18, height: 18)
                            .frame(width: metrics.minimalSlot)
                            .islandMatched("bubble-\(m.id)", in: ns)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(ActivityPresentation.accessibilityLabel(for: m))
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
            }
            .frame(width: wings.trailing - pad)
            .padding(.trailing, pad)
        }
        .frame(height: metrics.compactHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ActivityPresentation.accessibilityLabel(for: activity))
    }
}

/// Expanded surface: a header that straddles the notch, then the activity's interactive content.
struct ExpandedLayout: View {
    let model: IslandViewModel
    let metrics: IslandMetrics
    @Environment(\.islandNamespace) private var ns

    var body: some View {
        VStack(spacing: 0) {
            header.frame(height: metrics.compactHeight)
            ZStack(alignment: .top) {
                if let primary = model.primary {
                    ExpandedActivityView(activity: primary)
                        .id(primary.id)
                        .transition(IslandAnimation.contentTransition(reduceMotion: model.reduceMotion))
                } else {
                    HomeView()
                        .transition(IslandAnimation.contentTransition(reduceMotion: model.reduceMotion))
                }
            }
            // Natural height, independent of the (animating) container — reported so the Island sizes to fit.
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { geo in
                Color.clear.preference(key: ExpandedContentHeightKey.self, value: geo.size.height)
            })
            .onPreferenceChange(ExpandedContentHeightKey.self) { [style = model.expandedStyle] h in
                model.reportContentHeight(h, for: style)
            }
            .padding(.horizontal, 22)
            .padding(.top, IslandMetrics.expandedTopPadding)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                if let p = model.primary { Text(title(for: p)).lineLimit(1) }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(IslandPalette.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 22)
            Color.clear.frame(width: metrics.notchSize.width)
            ActivitySwitcher(model: model)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 20)
        }
    }

    /// Only media names its source (the content already says what every other activity is).
    private func title(for a: Activity) -> String {
        if case .media(let m) = a.content { return m.sourceName }
        return ""
    }
}

struct ExpandedContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Small activity tabs in the expanded header. They share geometry with the compact bubbles.
struct ActivitySwitcher: View {
    let model: IslandViewModel
    @Environment(\.islandNamespace) private var ns

    var body: some View {
        let items = Array(model.manager.ordered.prefix(model.manager.maxSecondaries + 1))
        if items.count > 1 {
            HStack(spacing: 4) {
                ForEach(items) { a in
                    let selected = a.id == model.primary?.id
                    Button { model.commands.perform(.ui(.select(activityID: a.id))) } label: {
                        MinimalView(activity: a)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(.white.opacity(selected ? 0.2 : 0.06)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressableStyle())
                    .islandMatched("bubble-\(a.id)", in: ns)
                    .accessibilityLabel(ActivityPresentation.accessibilityLabel(for: a))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
}
