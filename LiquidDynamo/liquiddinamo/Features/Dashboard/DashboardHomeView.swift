//
//  DashboardHomeView.swift
//  boringNotch
//
//  Created for Boring Notch
//

import Combine
import Defaults
import SwiftUI

@MainActor
final class DashboardHomeViewModel: ObservableObject {
    @Published var isBrightnessExpanded: Bool = false
}

struct DashboardHomeView: View {
    @EnvironmentObject var vm: LiquidViewModel
    @ObservedObject var coordinator = LiquidViewCoordinator.shared
    @ObservedObject var statsService = SystemStatsService.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @ObservedObject var brightnessService = MultiDisplayBrightnessService.shared
    @StateObject private var homeVM = DashboardHomeViewModel()
    let albumArtNamespace: Namespace.ID

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left: Now Playing Card
            MusicPlayerView(albumArtNamespace: albumArtNamespace)
                .padding(10)
                .liquidGlassCard(
                    cornerRadius: 20,
                    tint: Defaults[.playerColorTinting] ? Color(nsColor: MusicManager.shared.avgColor) : nil
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Right: Quick Controls Dashboard Card
            VStack(alignment: .leading, spacing: 8) {
                // MARK: Compact CPU & Memory Readout
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Premium3DIconView(.cpu, size: 13, interactive: false)
                        Text("SYSTEM LOAD")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("\(Int(statsService.overallCPU))%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(cpuColor(statsService.overallCPU))
                    }

                    // Mini CPU bar
                    GeometryReader { geo in
                        let width = geo.size.width
                        let progress = CGFloat(min(max(statsService.overallCPU / 100.0, 0), 1.0))
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 5)
                            Capsule()
                                .fill(cpuColor(statsService.overallCPU))
                                .frame(width: max(3, width * progress), height: 5)
                        }
                    }
                    .frame(height: 5)

                    // Memory line
                    HStack {
                        Text("Memory: \(statsService.formattedMemoryUsed) / \(statsService.formattedMemoryTotal)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(statsService.memoryPercentage))%")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(9)
                .liquidGlassCard(cornerRadius: 18)

                // MARK: Quick Volume Slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Button {
                            volumeManager.toggleMuteAction()
                        } label: {
                            Premium3DIconView(
                                .volume,
                                size: 14,
                                customTint: volumeManager.isMuted ? .red : nil,
                                interactive: false
                            )
                            .frame(width: 18)
                        }
                        .buttonStyle(.plain)

                        GeometryReader { geo in
                            let width = geo.size.width
                            let progress = CGFloat(volumeManager.isMuted ? 0 : volumeManager.rawVolume)
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.12))
                                    .frame(height: 6)

                                Capsule()
                                    .fill(volumeManager.hasVolumeControl ? (volumeManager.isMuted ? Color.gray : Color.accentColor) : Color.gray.opacity(0.5))
                                    .frame(width: max(0, min(width * progress, width)), height: 6)
                            }
                            .frame(height: 18)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { g in
                                        guard volumeManager.hasVolumeControl else { return }
                                        let pct = Float(max(0, min(1, g.location.x / width)))
                                        volumeManager.setAbsolute(pct)
                                    }
                            )
                        }
                        .frame(height: 18)

                        Text("\(Int(volumeManager.rawVolume * 100))%")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 26, alignment: .trailing)
                    }
                }
                .padding(9)
                .liquidGlassCard(cornerRadius: 18)

                // MARK: Display Brightness Sliders (Collapsible if > 2)
                VStack(alignment: .leading, spacing: 6) {
                    let displays = brightnessService.displays
                    let visibleDisplays = (displays.count <= 2 || homeVM.isBrightnessExpanded) ? displays : Array(displays.prefix(1))

                    ForEach(visibleDisplays) { display in
                        MiniDisplaySliderRow(display: display)
                    }

                    if displays.count > 2 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                homeVM.isBrightnessExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(homeVM.isBrightnessExpanded ? "Collapse" : "+\(displays.count - 1) more displays")
                                    .font(.system(size: 9, weight: .semibold))
                                Image(systemName: homeVM.isBrightnessExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 8))
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
                .padding(9)
                .liquidGlassCard(cornerRadius: 18)
            }
            .frame(width: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            statsService.start()
            brightnessService.refreshDisplays()
        }
        .onDisappear {
            if !Defaults[.showCollapsedCPUWing] && coordinator.currentView != .stats {
                statsService.stop()
            }
        }
    }

    private var volumeIcon: String {
        if volumeManager.isMuted || volumeManager.rawVolume == 0 {
            return "speaker.slash.fill"
        } else if volumeManager.rawVolume < 0.33 {
            return "speaker.wave.1.fill"
        } else if volumeManager.rawVolume < 0.66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }

    private func cpuColor(_ val: Double) -> Color {
        if val >= 80 { return .red }
        if val >= 50 { return .orange }
        return .green
    }
}

// MARK: - Mini Display Slider Row

private struct MiniDisplaySliderRow: View {
    @ObservedObject var display: ManagedDisplay
    @ObservedObject var brightnessService = MultiDisplayBrightnessService.shared

    var body: some View {
        HStack(spacing: 6) {
            Premium3DIconView(
                display.isBuiltIn ? .desktopMac : .brightness,
                size: 13,
                interactive: false
            )
            .frame(width: 14)

            GeometryReader { geo in
                let width = geo.size.width
                let progress = CGFloat(display.brightness)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 6)
                    Capsule()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: max(0, min(width * progress, width)), height: 6)
                }
                .frame(height: 16)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            let pct = Float(max(0, min(1, g.location.x / width)))
                            brightnessService.setBrightness(pct, for: display)
                        }
                )
            }
            .frame(height: 16)

            Text("\(Int(display.brightness * 100))%")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .trailing)
        }
    }
}
