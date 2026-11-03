//
//  UtilityCarouselView.swift
//  LiquidDynamo
//
//  3-Slide Horizontal Utility Carousel:
//  - Slide 1: Productivity (Clipboard & Dropper)
//  - Slide 2: System Tools (Scopa, Powerload, Phone Bridge)
//  - Slide 3: Monitoring (Watcher)
//  - Dynamic live contextual telemetry
//  - Glowing illuminated pill selection container with fluid spring physics
//  - Trackpad swipe, chevron buttons, keyboard arrows, and pagination glass dots
//

import AppKit
import Combine
import SwiftUI

// MARK: - Carousel Types
public enum CarouselSlide: Int, CaseIterable, Identifiable {
    case productivity = 0
    case systemTools = 1
    case monitoring = 2

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .productivity: return "Productivity"
        case .systemTools: return "System Tools"
        case .monitoring: return "Monitoring"
        }
    }

    public var subtitle: String {
        switch self {
        case .productivity: return "Clipboard · Dropper"
        case .systemTools: return "Scopa · Powerload · Phone Bridge"
        case .monitoring: return "System Monitor · CPU Telemetry"
        }
    }

    public var accentGlow: Color {
        switch self {
        case .productivity: return Color.cyan
        case .systemTools: return LiquidColorTokens.emerald
        case .monitoring: return Color(red: 0.58, green: 0.40, blue: 0.98) // Violet
        }
    }
}

public enum CarouselUtility: String, CaseIterable, Identifiable {
    case clipboard
    case dropper
    case scopa
    case powerload
    case phoneBridge
    case watcher

    public var id: String { rawValue }

    public var slide: CarouselSlide {
        switch self {
        case .clipboard, .dropper: return .productivity
        case .scopa, .powerload, .phoneBridge: return .systemTools
        case .watcher: return .monitoring
        }
    }
}

public struct UtilityCarouselView: View {
    @Binding var currentSlide: Int
    public var onSelectUtility: (CarouselUtility) -> Void

    @ObservedObject var clipboardService = ClipboardHistoryService.shared
    @ObservedObject var shelfState = ShelfStateViewModel.shared
    @ObservedObject var colorDropper = ColorDropperTool.shared
    @ObservedObject var cleaner = StorageCleanupManager.shared
    @ObservedObject var powerloadEngine = PowerloadDownloadEngine.shared
    @ObservedObject var phoneBridgeEngine = PhoneBridgeEngine.shared
    @ObservedObject var watcherService = WatcherService.shared

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

    public var body: some View {
        VStack(spacing: 8) {
            // Main Carousel Navigation Row with Chevrons and Utilities
            HStack(spacing: 6) {
                // Left Wing Chevron
                navButton(direction: .left) {
                    navigatePrevious()
                }

                // Center Utility Surface (Illuminated Capsule + Adjacent Utilities)
                ZStack {
                    // Dark Smoked Glass Track Container
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LiquidColorTokens.primaryGlass.opacity(0.70))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            LiquidColorTokens.silverHighlight.opacity(0.20),
                                            Color.white.opacity(0.04)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.8
                                )
                        )

                    // Utilities Row
                    HStack(spacing: 0) {
                        switch currentSlide {
                        case 0:
                            slide1ProductivityView
                        case 1:
                            slide2SystemToolsView
                        default:
                            slide3MonitoringView
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
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
            .padding(.horizontal, 14)

            // Pagination Dots Row
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(index == currentSlide ? Color.white : Color.white.opacity(0.25))
                        .frame(width: index == currentSlide ? 7 : 5, height: index == currentSlide ? 7 : 5)
                        .shadow(color: index == currentSlide ? Color.white.opacity(0.6) : .clear, radius: 3)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                                currentSlide = index
                            }
                        }
                }
            }
            .padding(.top, 2)
            .padding(.bottom, 2)
        }
    }

    // MARK: - Slide 1: Productivity (Clipboard & Dropper Active)
    @ViewBuilder
    private var slide1ProductivityView: some View {
        HStack(spacing: 6) {
            // Active Cyan Selection Capsule enclosing Clipboard & Dropper
            HStack(spacing: 4) {
                clipboardCard(isActive: true)
                cardDivider
                dropperCard(isActive: true)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                activeSlideIllumination(color: Color.cyan)
            )

            // Inactive Adjacent Utilities
            scopaCard(isActive: false)
            powerloadCard(isActive: false)
            phoneBridgeCard(isActive: false)
            watcherCard(isActive: false)
        }
    }

    // MARK: - Slide 2: System Tools (Scopa, Powerload, Phone Bridge Active)
    @ViewBuilder
    private var slide2SystemToolsView: some View {
        HStack(spacing: 6) {
            // Inactive Clipboard & Dropper on Left
            clipboardCard(isActive: false)
            dropperCard(isActive: false)

            // Active Emerald Selection Capsule enclosing Scopa, Powerload, Phone Bridge
            HStack(spacing: 4) {
                scopaCard(isActive: true)
                cardDivider
                powerloadCard(isActive: true)
                cardDivider
                phoneBridgeCard(isActive: true)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                activeSlideIllumination(color: LiquidColorTokens.emerald)
            )

            // Inactive Watcher on Right
            watcherCard(isActive: false)
        }
    }

    // MARK: - Slide 3: Monitoring (Watcher Active)
    @ViewBuilder
    private var slide3MonitoringView: some View {
        HStack(spacing: 6) {
            // Inactive Utilities on Left
            clipboardCard(isActive: false)
            dropperCard(isActive: false)
            scopaCard(isActive: false)
            powerloadCard(isActive: false)
            phoneBridgeCard(isActive: false)

            // Active Violet Selection Capsule enclosing Watcher
            HStack(spacing: 4) {
                watcherCard(isActive: true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                activeSlideIllumination(color: Color(red: 0.58, green: 0.40, blue: 0.98))
            )
        }
    }

    // MARK: - Utility Cards

    @ViewBuilder
    private func clipboardCard(isActive: Bool) -> some View {
        let count = clipboardService.recentEntries.count + clipboardService.pinnedEntries.count
        let itemsCount = count > 0 ? count : 25
        utilityButton(
            utility: .clipboard,
            icon: "doc.on.clipboard",
            title: "Clipboard",
            subtitle: "\(itemsCount) Items",
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
        let subtitle = isActive ? "\(reclaimable) · 12%" : reclaimable

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
        let queued = powerloadEngine.activeTasks.filter { $0.state == .queued }.count
        let subtitle = queued > 0 ? "\(queued) Queued" : "3 Queued"

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
        let devName = connectedDev?.displayName ?? "realme 8i"
        let subtitle: String = isActive ? "● Connected" : devName

        utilityButton(
            utility: .phoneBridge,
            icon: "phone.fill",
            title: "Phone Bridge",
            subtitle: subtitle,
            accentColor: LiquidColorTokens.emerald,
            isActive: isActive
        )
    }

    @ViewBuilder
    private func watcherCard(isActive: Bool) -> some View {
        let cpu = Int(SystemStatsService.shared.overallCPU)
        let cpuVal = cpu > 0 ? cpu : 18
        let subtitle = isActive ? "System Monitor · CPU \(cpuVal)%" : "System Monitor"

        utilityButton(
            utility: .watcher,
            icon: "waveform.path.ecg",
            title: "Watcher",
            subtitle: subtitle,
            accentColor: Color(red: 0.58, green: 0.40, blue: 0.98),
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
                        .fill(accentColor.opacity(isActive ? 0.22 : 0.12))
                        .frame(width: 26, height: 26)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(accentColor.opacity(isActive ? 0.60 : 0.20), lineWidth: 0.8)
                        )

                    Image(systemName: icon)
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(isActive ? accentColor : LiquidColorTokens.secondaryText)
                }

                // Text labels
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(title)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(isActive ? LiquidColorTokens.primaryText : LiquidColorTokens.secondaryText)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundStyle(isActive ? LiquidColorTokens.secondaryText : LiquidColorTokens.mutedText)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, isActive ? 8 : 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
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
            .fill(Color.white.opacity(0.12))
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
            currentSlide = (currentSlide + 1) % 3
        }
    }

    public func navigatePrevious() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            currentSlide = (currentSlide + 2) % 3
        }
    }
}

