import SwiftUI

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    UI.controlFill
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Four bars that bounce while playing, like the Dynamic Island's.
struct LevelMeter: View {
    let playing: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !playing)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    let phase = t * (2.6 + Double(i) * 0.7) + Double(i) * 1.3
                    let h: CGFloat = playing ? 4 + 10 * CGFloat(0.5 + 0.5 * sin(phase)) : 3
                    Capsule()
                        .fill(Color.white.opacity(playing ? 0.95 : 0.5))
                        .frame(width: 3, height: h)
                }
            }
            .frame(height: 14, alignment: .bottom)
        }
    }
}

/// One chip per stream the controller can see (app icon, short name, bars while it plays); tap one
/// to switch the island to it. Chips keep their natural width and wrap onto more rows, so no label
/// is ever clipped.
struct SourcePicker: View {
    let sources: [NowPlaying]
    let current: NowPlaying
    let select: (NowPlaying) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(sources, id: \.sourceKey) { source in
                let selected = source.sourceKey == current.sourceKey
                Button { select(source) } label: {
                    HStack(spacing: 5) {
                        Image(nsImage: source.icon).resizable().frame(width: 14, height: 14)
                        Text(Self.caption(for: source, among: sources))
                            .font(.system(size: 10.5, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize()
                        if source.isPlaying {
                            Image(systemName: "waveform").font(.system(size: 9, weight: .bold))
                        }
                    }
                    .foregroundStyle(selected ? Theme.onAccent : .white)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(selected ? Theme.accent : UI.controlFill, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(source.title.isEmpty ? source.player.name : "\(source.player.name) · \(source.title)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The app's short name. When the same app has several streams, the site tells them apart
    /// ("Brave · youtube.com"), or the start of the title when the sites match too.
    static func caption(for source: NowPlaying, among all: [NowPlaying]) -> String {
        let twins = all.filter { $0.player == source.player }
        guard twins.count > 1 else { return source.player.label }
        let hosts = Set(twins.map(\.sourceHost))
        if hosts.count == twins.count, !source.sourceHost.isEmpty {
            return "\(source.player.label) · \(source.sourceHost)"
        }
        guard !source.title.isEmpty else { return source.player.label }
        let short = source.title.count > 18
            ? String(source.title.prefix(17)).trimmingCharacters(in: .whitespaces) + "…"
            : source.title
        return "\(source.player.label) · \(short)"
    }
}

/// Lays children out left to right and starts a new row when the width runs out.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += row + spacing
                row = 0
            }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: width.isFinite ? width : widest, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += row + spacing
                row = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

/// Now Playing row for the hover readout: artwork, title/artist, scrubber, transport.
struct MediaCard: View {
    let media: NowPlaying
    @ObservedObject var controller: MediaController

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button(action: controller.openPlayer) {
                    ArtworkView(image: media.artwork, size: 48, radius: 11)
                }
                .buttonStyle(.plain)
                .help("Open \(media.player.name)")

                VStack(alignment: .leading, spacing: 3) {
                    Text(media.title.isEmpty ? media.player.name : media.title)
                        .font(UI.title())
                        .lineLimit(1)
                    Text(media.subtitle.isEmpty ? media.player.name : media.subtitle)
                        .font(UI.body(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    ProgressStrip(media: media, onSeek: controller.seek)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 2) {
                    TransportButton(symbol: "backward.fill", glyph: 13, size: 28) { controller.previous() }
                    TransportButton(symbol: media.isPlaying ? "pause.fill" : "play.fill", glyph: 18, size: 32) {
                        controller.togglePlayPause()
                    }
                    TransportButton(symbol: "forward.fill", glyph: 13, size: 28) { controller.next() }
                }
            }
            if controller.sources.count > 1 {
                SourcePicker(sources: controller.sources, current: media, select: controller.select)
            }
        }
        .islandCard(padding: 12)
    }
}

struct TransportButton: View {
    let symbol: String
    var glyph: CGFloat = 16
    var size: CGFloat = 36
    var filled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: glyph, weight: .bold))
                .frame(width: size, height: size)
                .background(filled ? UI.controlFill : Color.clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct ProgressStrip: View {
    let media: NowPlaying
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let elapsed = media.liveElapsed
            let fraction = media.duration > 0 ? min(max(elapsed / media.duration, 0), 1) : 0
            HStack(spacing: 8) {
                Text(Self.clock(elapsed))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(UI.track)
                        Capsule().fill(Theme.accent).frame(width: geo.size.width * fraction)
                    }
                    .contentShape(Rectangle().inset(by: -6))
                    .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                        guard media.duration > 0 else { return }
                        let f = min(max(value.location.x / geo.size.width, 0), 1)
                        onSeek(media.duration * f)
                    })
                }
                .frame(height: 4)
                Text(media.duration > 0 ? Self.clock(media.duration) : "–:––")
            }
            .font(UI.caption())
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
    }

    static func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Shade (notification-centre style)

/// The large Now Playing card for the shade: artwork, title/artist, full-width scrubber, centred
/// transport with a filled play button, and the global output-volume slider.
struct ShadeMediaCard: View {
    let media: NowPlaying
    @ObservedObject var controller: MediaController

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Button(action: controller.openPlayer) {
                    ArtworkView(image: media.artwork, size: 60, radius: 14)
                }
                .buttonStyle(.plain)
                .help("Open \(media.player.name)")

                VStack(alignment: .leading, spacing: 3) {
                    Text(media.title.isEmpty ? media.player.name : media.title)
                        .font(UI.title(15))
                        .lineLimit(1)
                    Text(media.subtitle.isEmpty ? media.player.name : media.subtitle)
                        .font(UI.body(12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Image(systemName: "waveform").font(.system(size: 9, weight: .semibold))
                        Text(media.player.name).font(UI.caption())
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }

            if controller.sources.count > 1 {
                SourcePicker(sources: controller.sources, current: media, select: controller.select)
            }

            ProgressStrip(media: media, onSeek: controller.seek)

            HStack(spacing: 22) {
                Spacer()
                TransportButton(symbol: "backward.fill", glyph: 18, size: 40) { controller.previous() }
                TransportButton(symbol: media.isPlaying ? "pause.fill" : "play.fill", glyph: 22, size: 52, filled: true) {
                    controller.togglePlayPause()
                }
                TransportButton(symbol: "forward.fill", glyph: 18, size: 40) { controller.next() }
                Spacer()
            }

            VolumeSlider(controller: controller)
        }
        .foregroundStyle(.white)
        .islandCard()
    }
}

/// System output volume. Global — it moves whatever is making sound, browser audio included.
struct VolumeSlider: View {
    @ObservedObject var controller: MediaController

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill").font(.system(size: 10, weight: .semibold))
            GeometryReader { geo in
                let x = geo.size.width * controller.systemVolume
                ZStack(alignment: .leading) {
                    Capsule().fill(UI.track).frame(height: 5)
                    Capsule().fill(Theme.accent).frame(width: x, height: 5)
                    Circle().fill(.white)
                        .frame(width: 14, height: 14)
                        .offset(x: x - 7)
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle().inset(by: -8))
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    controller.setSystemVolume(value.location.x / geo.size.width)
                })
            }
            .frame(height: 14)
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.secondary)
    }
}
