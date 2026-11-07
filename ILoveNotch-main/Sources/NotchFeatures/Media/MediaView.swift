// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

/// The media tab: artwork and track details over a soft glow of the cover, a wavy seek bar you can
/// drag, animated controls with shuffle and repeat, and a waveform along the bottom, all tinted from
/// the artwork. Small buttons open panels in its place: the player's list, Music's lyrics, and where
/// sound plays. Two fingers swiped sideways skip tracks. The animated parts run at most 30 fps, and
/// only while music plays and the tab is on screen.
struct MediaView: View {
    let media: MediaFeature

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// Where the seek bar is being dragged to, 0...1.
    @State private var scrub: Double?
    @State private var backTaps = 0
    @State private var forwardTaps = 0
    /// What shows in place of the player, when one is open.
    @State private var panel: Panel?

    enum Panel: Hashable {
        case list, lyrics, output
    }

    private var tint: Color { media.accent?.color ?? .white }

    var body: some View {
        if let now = media.nowPlaying {
            Group {
                if let panel = shownPanel {
                    panelView(panel, now).transition(.opacity)
                } else {
                    player(now).transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: shownPanel)
            .background { glow }
            .onChange(of: now.title) {
                if shownPanel == .list { media.loadList() }  // what's next moves on with the track
            }
        } else {
            idle
        }
    }

    /// The open panel, while the player still offers it.
    private var shownPanel: Panel? {
        switch panel {
        case .list: media.scriptedPlayer != nil ? .list : nil
        case .lyrics: media.lyrics != nil ? .lyrics : nil
        case .output: media.outputControl != nil ? .output : nil
        case nil: nil
        }
    }

    private func show(_ panel: Panel?) {
        if panel == .list { media.loadList() }
        self.panel = panel
    }

    /// Shorter notches drop the waveform first, then shrink the artwork, then move the controls up
    /// beside the track, so the player never clips.
    private func player(_ now: NowPlaying) -> some View {
        ViewThatFits(in: .vertical) {
            player(now, artwork: 72, waveform: true)
            player(now, artwork: 72, waveform: false)
            player(now, artwork: 52, waveform: false)
            player(now, artwork: 52, waveform: false, inline: true)
        }
        .background {
            SwipeCatcher { forward in
                guard media.hasControls else { return }
                if forward { forwardTaps += 1 } else { backTaps += 1 }
                media.send(forward ? .nextTrack : .previousTrack)
            }
        }
    }

    /// `inline` puts the controls beside the track, and shuffle and repeat with the small buttons
    /// under it, in place of the app it plays in.
    private func player(_ now: NowPlaying, artwork size: CGFloat, waveform: Bool, inline: Bool = false)
        -> some View
    {
        let animating = now.isPlaying && !reduceMotion
        return VStack(spacing: 8) {
            HStack(spacing: 14) {
                artwork(size)
                details(now, inline: inline)
                if inline { controls(now, modes: false) }
            }
            // One timeline drives the wave, the waveform, and the times, and stops when paused.
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !animating)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                VStack(spacing: 8) {
                    seekBar(now, at: context.date, phase: time * 2.4)
                    if !inline { controls(now, modes: media.hasModes) }
                    if waveform {
                        let heard = media.audio.isHearing ? media.audio.bands : []
                        Spacer(minLength: 0)
                        Waveform(level: animating ? 1 : 0, time: time, tint: tint, bands: heard)
                            .frame(height: 18)
                            .fadingEdges(.horizontal, length: 28)
                            .animation(.easeInOut(duration: 0.5), value: animating)
                            .accessibilityHidden(true)
                    }
                }
            }
            if media.automationDenied, let player = media.scriptedPlayer {
                permissionHint(player)
            }
        }
    }

    // MARK: Parts

    private func artwork(_ size: CGFloat) -> some View {
        Button(action: media.openPlayer) {
            ZStack {
                if let image = media.artwork {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                } else {
                    LinearGradient(
                        colors: [tint.opacity(0.45), tint.opacity(0.12)], startPoint: .topLeading,
                        endPoint: .bottomTrailing)
                    Image(systemName: "music.note").font(.system(size: size * 0.36)).opacity(0.7)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
            .shadow(color: tint.opacity(0.45), radius: 12, y: 4)
            .animation(.easeInOut(duration: 0.16), value: media.artwork)
        }
        .buttonStyle(PressableButtonStyle())
        .help("Open the player")
        .accessibilityLabel("Open the player")
    }

    private func details(_ now: NowPlaying, inline: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(now.title)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)
                .id(now.title)
                .transition(.push(from: .bottom))
            if let subtitle = now.artist ?? now.album {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .id(subtitle)
                    .transition(.push(from: .bottom))
            }
            accessories(now, inline: inline)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.82), value: now.title)
    }

    /// Under the track: the app it plays in and the panels' buttons, or, beside inline controls,
    /// shuffle and repeat with the panels' buttons.
    @ViewBuilder private func accessories(_ now: NowPlaying, inline: Bool) -> some View {
        if inline {
            HStack(spacing: 6) {
                if media.hasModes {
                    shuffleButton(size: 11.5)
                    repeatButton(size: 11.5)
                }
                panelButtons
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: 6) {
                sourceApp(now)
                Spacer(minLength: 0)
                panelButtons
            }
        }
    }

    @ViewBuilder private var panelButtons: some View {
        if media.scriptedPlayer != nil {
            smallButton(media.scriptedPlayer == .spotify ? "clock.arrow.circlepath" : "list.bullet", size: 11.5) {
                show(.list)
            }
            .help(media.scriptedPlayer == .spotify ? "Recently played" : "Up next")
            .accessibilityLabel(media.scriptedPlayer == .spotify ? "Recently played" : "Up next")
        }
        if media.lyrics != nil {
            smallButton("quote.bubble", size: 11.5) { show(.lyrics) }
                .help("Lyrics")
                .accessibilityLabel("Lyrics")
        }
        if media.outputControl != nil {
            smallButton("airplayaudio", size: 11.5) { show(.output) }
                .help("Output and volume")
                .accessibilityLabel("Output and volume")
        }
    }

    @ViewBuilder private func sourceApp(_ now: NowPlaying) -> some View {
        if let id = now.appBundleID, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            HStack(spacing: 4) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                    .resizable()
                    .frame(width: 13, height: 13)
                Text(FileManager.default.displayName(atPath: app.path))
                    .lineLimit(1)
            }
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.45))
        }
    }

    private func seekBar(_ now: NowPlaying, at date: Date, phase: Double) -> some View {
        let duration = now.duration ?? 0
        let position = scrub.map { $0 * duration } ?? now.position(at: date) ?? 0
        let canSeek = media.hasControls && duration > 0
        return HStack(spacing: 8) {
            RollingTime(position)
                .frame(minWidth: 34, alignment: .trailing)
            GeometryReader { proxy in
                WavySeekBar(
                    progress: duration > 0 ? position / duration : 0,
                    amplitude: now.isPlaying && !reduceMotion && scrub == nil ? 1 : 0,
                    phase: phase, tint: tint
                )
                .animation(.easeInOut(duration: 0.45), value: now.isPlaying)
                .animation(.easeInOut(duration: 0.2), value: scrub == nil)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in scrub = min(max(drag.location.x / proxy.size.width, 0), 1) }
                        .onEnded { _ in
                            if let scrub { media.seek(to: scrub * duration) }
                            scrub = nil
                        },
                    isEnabled: canSeek)
            }
            .frame(height: 18)
            HStack(spacing: 0) {
                Text("-")
                RollingTime(duration - position, countsDown: true)
            }
            .frame(minWidth: 38, alignment: .leading)
        }
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.55))
        .opacity(duration > 0 ? 1 : 0.4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(formatTime(position, roundingUp: false)) of \(formatTime(duration, roundingUp: false))")
    }

    /// Back, play or pause, and ahead: by track, or by 15 seconds where the player skips that way
    /// (podcasts, audiobooks). `modes` puts shuffle and repeat at either end.
    private func controls(_ now: NowPlaying, modes: Bool) -> some View {
        let interval = now.skipsByInterval
        return HStack(spacing: modes ? 22 : 30) {
            if modes { shuffleButton(size: 13) }
            Button {
                backTaps += 1
                media.send(interval ? .skipBackward : .previousTrack)
            } label: {
                Image(systemName: interval ? "gobackward.15" : "backward.fill")
                    .symbolEffect(.bounce.down, value: backTaps)
            }
            .accessibilityLabel(interval ? "Back 15 seconds" : "Previous track")
            Button {
                media.send(.togglePlayPause)
            } label: {
                Image(systemName: now.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .contentTransition(.symbolEffect(.replace.downUp))
                    .foregroundStyle(.black)
                    .frame(width: 40, height: 40)
                    .background(tint, in: Circle())
            }
            .accessibilityLabel(now.isPlaying ? "Pause" : "Play")
            Button {
                forwardTaps += 1
                media.send(interval ? .skipForward : .nextTrack)
            } label: {
                Image(systemName: interval ? "goforward.15" : "forward.fill")
                    .symbolEffect(.bounce.down, value: forwardTaps)
            }
            .accessibilityLabel(interval ? "Forward 15 seconds" : "Next track")
            if modes { repeatButton(size: 13) }
        }
        .font(.system(size: 17, weight: .semibold))
        .buttonStyle(PressableButtonStyle())
        .disabled(!media.hasControls)
    }

    /// Lit in the cover's color while on.
    private func shuffleButton(size: CGFloat) -> some View {
        let on = media.shuffle == true
        return smallButton("shuffle", size: size, lit: on, action: media.toggleShuffle)
            .help(on ? "Shuffle is on" : "Shuffle")
            .accessibilityLabel("Shuffle")
            .accessibilityValue(on ? "On" : "Off")
    }

    private func repeatButton(size: CGFloat) -> some View {
        let mode = media.repeatMode ?? .off
        let (help, value) =
            switch mode {
            case .off: ("Repeat", "Off")
            case .all: ("Repeating all", "All")
            case .one: ("Repeating this track", "One")
            }
        let symbol = mode == .one ? "repeat.1" : "repeat"
        return smallButton(symbol, size: size, lit: mode != .off, action: media.cycleRepeat)
            .help(help)
            .accessibilityLabel("Repeat")
            .accessibilityValue(value)
    }

    private func smallButton(_ symbol: String, size: CGFloat, lit: Bool = false, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(lit ? tint : .white.opacity(0.55))
                .frame(width: size + 9, height: size + 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .animation(.easeOut(duration: 0.15), value: lit)
    }

    /// The user turned down scripting the player, which its controls need here.
    private func permissionHint(_ player: ScriptedPlayer) -> some View {
        Button {
            NSWorkspace.shared.open(.privacySettings("Privacy_Automation"))
        } label: {
            Text("Allow ILoveNotch to control \(player.name) in Privacy & Security › Automation")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .buttonStyle(.plain)
    }

    // MARK: Panels

    /// A panel in the player's place: a back button and its title, over its content.
    private func panelView(_ panel: Panel, _ now: NowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    show(nil)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 20, height: 20)
                        .background(.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(PressableButtonStyle())
                .help("Back to the player")
                .accessibilityLabel("Back to the player")
                VStack(alignment: .leading, spacing: 0) {
                    Text(title(of: panel)).font(.system(size: 12, weight: .semibold))
                    Text(now.title).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            Group {
                switch panel {
                case .list: list
                case .lyrics: lyricsText
                case .output: media.outputControl?(now.appBundleID)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func title(of panel: Panel) -> String {
        switch panel {
        case .list:
            guard media.scriptedPlayer == .music else { return "Recently Played" }
            let playlist = media.queue?.title ?? ""
            if playlist.isEmpty { return "Up Next" }
            // Shuffled, Music still lists the playlist in its own order, not the order it plays in.
            return media.shuffle == true ? "From \(playlist)" : "Up Next from \(playlist)"
        case .lyrics: return "Lyrics"
        case .output: return "Output"
        }
    }

    @ViewBuilder private var list: some View {
        if let queue = media.queue {
            if queue.items.isEmpty {
                Text(emptyList(queue))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .multilineTextAlignment(.center)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 1) {
                        ForEach(queue.items) { item in
                            QueueRow(item: item, tint: tint) { media.play(item) }
                        }
                    }
                }
                .fadingEdges(.vertical, length: 8)
            }
        } else if media.automationDenied, let player = media.scriptedPlayer {
            permissionHint(player).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func emptyList(_ queue: PlayerQueue) -> String {
        if media.scriptedPlayer == .spotify {
            return "Spotify keeps its queue to itself. Tracks you play show up here, to play again."
        }
        return queue.title.isEmpty
            ? "Music doesn't share what plays next from here." : "Nothing plays after this in \(queue.title)."
    }

    private var lyricsText: some View {
        ScrollView(.vertical) {
            Text(media.lyrics ?? "")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .fadingEdges(.vertical, length: 8)
    }

    /// A soft, saturated blur of the cover behind the whole notch; the notch clips it to its outline.
    @ViewBuilder private var glow: some View {
        if let image = media.artwork, !reduceTransparency {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .blur(radius: 50)
                .saturation(1.3)
                .opacity(0.35)
                .padding(-60)
                .allowsHitTesting(false)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: media.artwork)
        }
    }

    /// The smallest notch drops the note, so the message never clips.
    private var idle: some View {
        ViewThatFits(in: .vertical) {
            idle(note: true)
            idle(note: false)
        }
    }

    private func idle(note: Bool) -> some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            if note {
                Image(systemName: "music.note")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 46, height: 46)
                    .background(.white.opacity(0.08), in: Circle())
            }
            Text("Nothing playing").font(.headline)
            Text(
                media.source == .adapter
                    ? "Play something in Music, Spotify, a browser, or any app that reports what it's playing."
                    : "Play something in Music or Spotify."
            )
            .font(.caption)
            .foregroundStyle(.white.opacity(0.55))
            .multilineTextAlignment(.center)
            .frame(maxWidth: 320)
            Spacer(minLength: 0)
            Waveform(level: 0, time: 0, tint: .white)
                .frame(height: 14)
                .fadingEdges(.horizontal, length: 40)
                .opacity(0.4)
                .accessibilityHidden(true)
        }
    }
}

/// A track in the list: its title and artist, and its length. A click plays it.
private struct QueueRow: View {
    let item: QueueItem
    let tint: Color
    let play: () -> Void

    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        Button(action: play) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 10)
                    .opacity(hovering ? 1 : 0)
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.title).font(.system(size: 12, weight: .medium))
                    if let artist = item.artist {
                        Text(artist).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                if let duration = item.duration, duration > 0 {
                    Text(formatTime(duration, roundingUp: false))
                        .font(.system(size: 10.5))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.white.opacity(hovering ? 0.08 : 0), in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Play \(item.title)")
        .accessibilityLabel(item.artist.map { "\(item.title), \($0)" } ?? item.title)
        .accessibilityHint("Plays it")
    }
}

/// Two fingers swiped sideways over the player skip tracks: left for the next, right for the one
/// before, once per swipe. A local monitor sees only scrolls already addressed to this app, so it
/// costs nothing while the pointer is elsewhere; it's installed only while the player is on screen.
private struct SwipeCatcher: NSViewRepresentable {
    let onSwipe: (_ forward: Bool) -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView() }

    func updateNSView(_ view: CatcherView, context: Context) { view.onSwipe = onSwipe }

    final class CatcherView: NSView {
        var onSwipe: ((Bool) -> Void)?
        private var monitor: Any?
        /// How far the fingers have moved this swipe, rightward and downward.
        private var travel = CGSize.zero
        private var fired = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event) }
                return event
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }  // clicks belong to the player

        private func handle(_ event: NSEvent) {
            // Trackpad swipes only (they have phases), not their momentum or a mouse's wheel.
            guard event.window === window, event.momentumPhase.isEmpty, !event.phase.isEmpty,
                bounds.contains(convert(event.locationInWindow, from: nil))
            else { return }
            if event.phase.contains(.began) {
                travel = .zero
                fired = false
            }
            // With natural scrolling the deltas follow the fingers; otherwise they're inverted.
            let sign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
            travel.width += event.scrollingDeltaX * sign
            travel.height += event.scrollingDeltaY * sign
            if !fired, let forward = swipeDirection(travel) {
                fired = true
                onSwipe?(forward)
            }
        }
    }
}

/// Whether fingers that moved by `travel` swiped to the next track (left) or the one before
/// (right): far enough, and mostly sideways. Nil otherwise.
func swipeDirection(_ travel: CGSize) -> Bool? {
    guard abs(travel.width) > 60, abs(travel.width) > abs(travel.height) * 2 else { return nil }
    return travel.width < 0
}
