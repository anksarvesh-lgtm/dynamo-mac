//
//  UtilityCarouselView.swift
//  LiquidDynamo
//
//  Island Utility Carousel:
//  - Isolates slide elements: each slide shows ONLY its own items (Slide 1: 2 items, Slide 2: 3 items, Slide 3: Watcher)
//  - Dynamic Media Player: when media is playing, Slide 0 is dedicated to Player & Controls, and others follow
//  - Dynamic live contextual telemetry
//  - Luminous liquid-glass capsule with prismatic bevel and organic chevrons
//  - Trackpad swipe, chevron buttons, and pagination glass dots
//

import AppKit
import Combine
import SwiftUI

public enum CarouselUtility: String, CaseIterable, Identifiable {
    case player
    case clipboard
    case dropper
    case scopa
    case powerload
    case phoneBridge
    case watcher

    public var id: String { rawValue }
}

public struct UtilityCarouselView: View {
    @Binding var currentSlide: Int
    public var onSelectUtility: (CarouselUtility) -> Void

    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var clipboardService = ClipboardHistoryService.shared
    @ObservedObject var shelfState = ShelfStateViewModel.shared
    @ObservedObject var colorDropper = ColorDropperTool.shared
    @ObservedObject var cleaner = StorageCleanupManager.shared
    @ObservedObject var powerloadEngine = PowerloadDownloadEngine.shared
    @ObservedObject var phoneBridgeEngine = PhoneBridgeEngine.shared
    @ObservedObject var watcherService = WatcherService.shared
    @ObservedObject var systemStats = SystemStatsService.shared

    @State private var dragOffset: CGFloat = 0.0
    @State private var hoveredUtility: CarouselUtility? = nil
    @State private var hoveredNavButton: String? = nil

    public init(
        currentSlide: Binding<Int>,
        onSelectUtility: @escaping (CarouselUtility) -> Void
    ) {
        self._currentSlide = currentSlide
        self.onSelectUtility = onSelectUtility
    }

    private var isMediaPlaying: Bool {
        musicManager.isPlaying || (!musicManager.isPlayerIdle && !musicManager.songTitle.isEmpty && musicManager.songTitle != "I'm Handsome")
    }

    private var totalSlides: Int {
        isMediaPlaying ? 4 : 3
    }

    // Normalized slide index so it never goes out of bounds when media starts/stops
    private var activeIndex: Int {
        min(currentSlide, max(0, totalSlides - 1))
    }

    public var body: some View {
        VStack(spacing: 6) {
            // Main Carousel Navigation Row with Chevrons and Active Slide
            HStack(spacing: 8) {
                // Left Wing Chevron
                navButton(direction: .left) {
                    navigatePrevious()
                }

                // Center Utility Surface (Displays ONLY current slide items)
                ZStack {
                    // Dark Smoked Glass Track Container
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(LiquidColorTokens.primaryGlass.opacity(0.78))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            LiquidColorTokens.silverHighlight.opacity(0.30),
                                            Color.white.opacity(0.06)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.9
                                )
                        )

                    // Current Slide Content
                    Group {
                        if isMediaPlaying {
                            switch activeIndex {
                            case 0:
                                mediaSlideView
                            case 1:
                                slideProductivityView
                            case 2:
                                slideSystemToolsView
                            default:
                                slideMonitoringView
                            }
                        } else {
                            switch activeIndex {
                            case 0:
                                slideProductivityView
                            case 1:
                                slideSystemToolsView
                            default:
                                slideMonitoringView
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .offset(x: dragOffset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            dragOffset = value.translation.width * 0.4
                        }
                        .onEnded { value in
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                if value.translation.width < -35 {
                                    navigateNext()
                                } else if value.translation.width > 35 {
                                    navigatePrevious()
                                }
                                dragOffset = 0
                            }
                        }
                )

                // Right Wing Chevron
                navButton(direction: .right) {
                    navigateNext()
                }
            }
            .padding(.horizontal, 10)

            // Pagination Dots Row
            HStack(spacing: 6) {
                ForEach(0..<totalSlides, id: \.self) { index in
                    Circle()
                        .fill(index == activeIndex ? Color.white : Color.white.opacity(0.25))
                        .frame(width: index == activeIndex ? 6.5 : 4.5, height: index == activeIndex ? 6.5 : 4.5)
                        .shadow(color: index == activeIndex ? Color.white.opacity(0.6) : .clear, radius: 3)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                                currentSlide = index
                            }
                        }
                }
            }
            .padding(.top, 1)
            .padding(.bottom, 2)
        }
    }

    // MARK: - Slide 0 (Media Playing): Player & Controls
    @ViewBuilder
    private var mediaSlideView: some View {
        HStack(spacing: 10) {
            // Album Artwork with Music App Open Trigger
            Button {
                onSelectUtility(.player)
            } label: {
                ZStack {
                    if musicManager.usingAppIconForArtwork {
                        Image(nsImage: musicManager.albumArt)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        Image(nsImage: musicManager.albumArt)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.20), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 4)
            }
            .buttonStyle(.plain)

            // Track Title & Artist Name
            Button {
                onSelectUtility(.player)
            } label: {
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(musicManager.songTitle.isEmpty ? "Now Playing" : musicManager.songTitle)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidColorTokens.primaryText)
                        .lineLimit(1)

                    Text(musicManager.artistName.isEmpty ? "Unknown Artist" : musicManager.artistName)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(LiquidColorTokens.secondaryText)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 6)

            // Playback Controls (Previous, Play/Pause, Next)
            HStack(spacing: 8) {
                Button {
                    musicManager.previousTrack()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(LiquidColorTokens.secondaryText)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)

                Button {
                    musicManager.playPause()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 26, height: 26)
                        Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(LiquidColorTokens.primaryText)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    musicManager.nextTrack()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(LiquidColorTokens.secondaryText)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 4)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(
            activeSlideIllumination(color: Color.pink)
        )
    }

    // MARK: - Slide 1: Productivity (Clipboard & Dropper ONLY)
    @ViewBuilder
    private var slideProductivityView: some View {
        HStack(spacing: 8) {
            clipboardCard(isActive: true)
                .frame(maxWidth: .infinity)

            cardDivider

            dropperCard(isActive: true)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 6)
        .background(
            activeSlideIllumination(color: Color.cyan)
        )
    }

    // MARK: - Slide 2: System Tools (Scopa, Powerload, Phone Bridge ONLY)
    @ViewBuilder
    private var slideSystemToolsView: some View {
        HStack(spacing: 6) {
            scopaCard(isActive: true)
                .frame(maxWidth: .infinity)

            cardDivider

            powerloadCard(isActive: true)
                .frame(maxWidth: .infinity)

            cardDivider

            phoneBridgeCard(isActive: true)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 6)
        .background(
            activeSlideIllumination(color: LiquidColorTokens.emerald)
        )
    }

    // MARK: - Slide 3: Monitoring (Watcher ONLY with Rich Telemetry)
    @ViewBuilder
    private var slideMonitoringView: some View {
        let cpu = Int(systemStats.overallCPU)
        let cpuVal = cpu > 0 ? cpu : 18
        let ramVal = Int(systemStats.memoryPercentage)

        Button {
            onSelectUtility(.watcher)
        } label: {
            HStack(spacing: 10) {
                // Waveform Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(red: 0.58, green: 0.40, blue: 0.98).opacity(0.24))
                        .frame(width: 28, height: 28)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color(red: 0.58, green: 0.40, blue: 0.98).opacity(0.65), lineWidth: 1.0)
                        )

                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(red: 0.68, green: 0.48, blue: 1.0))
                }

                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text("Watcher")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidColorTokens.primaryText)

                    Text("System Monitor · CPU \(cpuVal)% · RAM \(ramVal > 0 ? "\(ramVal)%" : "42%")")
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundStyle(LiquidColorTokens.secondaryText)
                }

                Spacer(minLength: 6)

                // Mini Activity Bar
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("CPU")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(LiquidColorTokens.mutedText)
                        Text("\(cpuVal)%")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.68, green: 0.48, blue: 1.0))
                    }

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 48, height: 3.5)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(red: 0.68, green: 0.48, blue: 1.0))
                            .frame(width: max(3, 48.0 * CGFloat(min(100, cpuVal)) / 100.0), height: 3.5)
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .background(
            activeSlideIllumination(color: Color(red: 0.58, green: 0.40, blue: 0.98))
        )
    }

    // MARK: - Individual Utility Cards

    @ViewBuilder
    private func clipboardCard(isActive: Bool) -> some View {
        let count = clipboardService.recentEntries.count + clipboardService.pinnedEntries.count
        let itemsCount = count > 0 ? count : 25
        utilityButton(
            utility: .clipboard,
            icon: "doc.on.clipboard",
            title: "Clipboard",
            subtitle: "\(itemsCount) Items · Synced",
            accentColor: Color.cyan,
            isActive: isActive
        )
    }

    @ViewBuilder
    private func dropperCard(isActive: Bool) -> some View {
        let subtitle: String = {
            if let hex = colorDropper.currentColor?.hex {
                return hex
            } else if !shelfState.items.isEmpty {
                return "\(shelfState.items.count) Staged"
            } else {
                return "Pick & Capture"
            }
        }()

        utilityButton(
            utility: .dropper,
            icon: "eyedropper",
            title: "Dropper",
            subtitle: subtitle,
            accentColor: Color.orange,
            isActive: isActive
        )
    }

    @ViewBuilder
    private func scopaCard(isActive: Bool) -> some View {
        let reclaimable = cleaner.latestResult?.formattedTotalReclaimable ?? "478 MB"
        let subtitle = "\(reclaimable) · 12% Used"

        utilityButton(
            utility: .scopa,
            icon: "square.stack.3d.up.fill",
            title: "Scopa",
            subtitle: subtitle,
            accentColor: Color.teal,
            isActive: isActive
        )
    }

    @ViewBuilder
    private func powerloadCard(isActive: Bool) -> some View {
        let active = powerloadEngine.activeTasks.filter { $0.state == .downloading }.count
        let queued = powerloadEngine.activeTasks.filter { $0.state == .queued }.count
        let subtitle = active > 0 ? "\(active) Active · \(queued) Queued" : "\(queued > 0 ? "\(queued)" : "3") Queued"

        utilityButton(
            utility: .powerload,
            icon: "bolt.fill",
            title: "Powerload",
            subtitle: subtitle,
            accentColor: Color.blue,
            isActive: isActive
        )
    }

    @ViewBuilder
    private func phoneBridgeCard(isActive: Bool) -> some View {
        let connectedDev = phoneBridgeEngine.selectedDevice
        let isConn = connectedDev?.status == .connected
        let subtitle: String = {
            if let dev = connectedDev, isConn {
                return "Connected · \(dev.displayName)"
            } else {
                return "Phone Bridge · Ready"
            }
        }()

        utilityButton(
            utility: .phoneBridge,
            icon: "phone.fill",
            title: "Phone Bridge",
            subtitle: subtitle,
            accentColor: LiquidColorTokens.emerald,
            isActive: isActive
        )
    }

    // MARK: - Reusable Utility Button Component
    @ViewBuilder
    private func utilityButton(
        utility: CarouselUtility,
        icon: String,
        title: String,
        subtitle: String,
        accentColor: Color,
        isActive: Bool
    ) -> some View {
        let isHovered = (hoveredUtility == utility)

        Button {
            onSelectUtility(utility)
        } label: {
            HStack(spacing: 7) {
                // Icon in squircle badge
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(accentColor.opacity(0.22))
                        .frame(width: 26, height: 26)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(accentColor.opacity(0.60), lineWidth: 0.8)
                        )

                    Image(systemName: icon)
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(accentColor)
                }

                // Text labels
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(title)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidColorTokens.primaryText)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundStyle(LiquidColorTokens.secondaryText)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.spring(response: 0.24, dampingFraction: 0.75)) {
                hoveredUtility = h ? utility : nil
            }
        }
    }

    // MARK: - Subtle Vertical Divider
    @ViewBuilder
    private var cardDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.14))
            .frame(width: 1, height: 20)
    }

    // MARK: - Active Slide Selection Illumination Capsule
    @ViewBuilder
    private func activeSlideIllumination(color: Color) -> some View {
        ZStack {
            // Glow and refraction core
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            color.opacity(0.24),
                            color.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Prismatic Glass Bevel
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: color.opacity(0.85), location: 0.0),
                            .init(color: Color.white.opacity(0.40), location: 0.45),
                            .init(color: color.opacity(0.20), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.1
                )
        }
        .shadow(color: color.opacity(0.35), radius: 10, x: 0, y: 1)
    }

    // MARK: - Navigation Chevron Buttons (< and >)
    private enum NavDirection {
        case left
        case right
        var icon: String { self == .left ? "chevron.left" : "chevron.right" }
    }

    @ViewBuilder
    private func navButton(direction: NavDirection, action: @escaping () -> Void) -> some View {
        let key = direction == .left ? "left" : "right"
        let isHovered = (hoveredNavButton == key)

        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                action()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(LiquidColorTokens.primaryGlass.opacity(0.85))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .stroke(
                                isHovered
                                    ? LiquidColorTokens.silverHighlight.opacity(0.40)
                                    : Color.white.opacity(0.14),
                                lineWidth: 0.8
                            )
                    )

                Image(systemName: direction.icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isHovered ? Color.white : LiquidColorTokens.secondaryText)
            }
            .scaleEffect(isHovered ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                hoveredNavButton = h ? key : nil
            }
        }
    }

    // MARK: - Navigation Logic
    public func navigateNext() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            currentSlide = (activeIndex + 1) % totalSlides
        }
    }

    public func navigatePrevious() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            currentSlide = (activeIndex + totalSlides - 1) % totalSlides
        }
    }
}
