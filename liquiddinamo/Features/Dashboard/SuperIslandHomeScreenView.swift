//
//  SuperIslandHomeScreenView.swift
//  LiquidDynamo
//
//  Created for LiquidDynamo
//
//  Multi-panel Home Dashboard combining Now Playing, Calendar, Weather, and MacLink Phone Deck.
//

import AppKit
import Combine
import Defaults
import EventKit
import SwiftUI

public struct SuperIslandHomeScreenView: View {
    @ObservedObject private var music = MusicManager.shared
    @ObservedObject private var spectrum = AudioSpectrumEngine.shared
    @ObservedObject private var calendarManager = CalendarManager.shared
    @ObservedObject private var weather = AmbientWeatherService.shared
    @ObservedObject private var phoneBridge = MacLinkBridgeService.shared
    @ObservedObject private var meetingFlight = MeetingFlightService.shared
    @ObservedObject private var coordinator = LiquidViewCoordinator.shared
    @ObservedObject private var deviceMonitor = DeviceMonitor.shared
    @ObservedObject private var clipboardService = ClipboardHistoryService.shared

    @Default(.showDashboardClipboard) private var showClipboard
    @Default(.hiddenDeviceIDs) private var hiddenDeviceIDs
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    /// Checks if at least one real external device is connected.
    private var hasConnectedDevices: Bool {
        deviceMonitor.sortedActiveDevices.contains { dev in
            if hiddenDeviceIDs.contains(dev.stableKey) { return false }
            let name = dev.displayName.lowercased()
            let model = dev.model.lowercased()
            let vendor = dev.vendor.lowercased()
            if name.contains("built-in") || model.contains("built-in") { return false }
            if name.contains("root hub") || model.contains("root hub") { return false }
            if name.contains("apple t2") || name.contains("ambient light") { return false }
            if name.contains("virtual") || vendor.contains("virtual") { return false }
            return true
        }
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Slot 1: Connected Devices (FIRST, strictly when >= 1 real external device is connected)
            if hasConnectedDevices {
                ConnectedDevicesIslandCardView()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96)),
                        removal: .opacity
                    ))

                homeDivider
            }

            // Panel: Now Playing Card
            nowPlayingCard
                .frame(maxWidth: .infinity, alignment: .topLeading)

            homeDivider

            // Panel: Calendar & MeetingFlight Card
            calendarCard
                .frame(maxWidth: .infinity, alignment: .topLeading)

            homeDivider

            // Panel: Clipboard History (when enabled) or Ambient Weather Card
            if showClipboard {
                ClipboardHistoryIslandCardView()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                weatherCard
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            homeDivider

            // Panel: MacLink Phone Bridge Deck
            phoneDeckCard
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 10)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.8), value: hasConnectedDevices)
    }

    private var homeDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.09))
            .frame(width: 1)
            .padding(.vertical, 6)
    }

    // MARK: - 1. Now Playing Card

    private var nowPlayingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                Text("NOW PLAYING")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.6))
                Spacer()

                if music.isPlaying {
                    // Mini live waveform visualizer
                    HStack(spacing: 1.5) {
                        ForEach(0..<4) { i in
                            waveformBar(at: i)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                // Artwork
                Image(nsImage: music.albumArt)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.12), lineWidth: 0.5))

                VStack(alignment: .leading, spacing: 2) {
                    Text(music.songTitle.isEmpty ? "No Media Playing" : music.songTitle)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)

                    Text(music.artistName.isEmpty ? "LiquidDynamo Player" : music.artistName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .lineLimit(1)

                    // Scrubber
                    HStack(spacing: 8) {
                        Button {
                            music.previousTrack()
                        } label: {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.white.opacity(0.75))
                        }
                        .buttonStyle(.plain)

                        Button {
                            music.playPause()
                        } label: {
                            Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.white)
                        }
                        .buttonStyle(.plain)

                        Button {
                            music.nextTrack()
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.white.opacity(0.75))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) {
                coordinator.currentView = .home
            }
        }
    }

    // MARK: - 2. Calendar Card

    private var calendarCard: some View {
        let upcoming = calendarManager.events.first(where: { $0.end > Date() })

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.red)
                Text("UPCOMING")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.6))
                Spacer()

                if let event = upcoming {
                    Text(timeBadge(for: event.start))
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.red)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.red.opacity(0.18)))
                }
            }

            if let event = upcoming {
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)

                    Text(eventTimeString(event))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.65))

                    if let url = event.url ?? (event.location.flatMap { URL(string: $0) }) {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "video.fill")
                                    .font(.system(size: 9))
                                Text("Join Flight")
                                    .font(.system(size: 9.5, weight: .bold))
                            }
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.green.opacity(0.8)))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text("No Upcoming Events")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.7))
                    Text("Schedule is clear")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) {
                coordinator.currentView = .calendar
            }
        }
    }

    // MARK: - 3. Weather Card

    private var weatherCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "cloud.sun.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.yellow)
                Text("ENVIRONMENT")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.6))
                Spacer()

                Button {
                    Defaults[.enableWeatherPrecipitation].toggle()
                } label: {
                    Image(systemName: Defaults[.enableWeatherPrecipitation] ? "drop.fill" : "drop")
                        .font(.system(size: 9))
                        .foregroundStyle(Defaults[.enableWeatherPrecipitation] ? Color.cyan : Color.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help(Defaults[.enableWeatherPrecipitation] ? "Atmospheric Precipitation: Enabled" : "Atmospheric Precipitation: Disabled")
            }

            HStack(spacing: 8) {
                Image(systemName: weatherConditionIcon(weather.condition))
                    .font(.system(size: 24))
                    .foregroundStyle(weatherConditionColor(weather.condition))

                VStack(alignment: .leading, spacing: 2) {
                    Text(weatherConditionName(weather.condition))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.white)

                    Text(Defaults[.enableWeatherPrecipitation] ? "Rain Particles Active" : "Liquid Atmosphere")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
            }
        }
    }

    // MARK: - 4. MacLink Phone Bridge Card

    private var phoneDeckCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.green)
                Text("MACLINK PHONE")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.6))
                Spacer()

                // Battery + Signal
                HStack(spacing: 4) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.white.opacity(0.8))
                    Text("\(phoneBridge.batteryLevel)%")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.green)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(phoneBridge.deviceName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)

                // Quick Phone Action Capsules
                HStack(spacing: 5) {
                    quickDeckButton(icon: "personalhotspot", title: "Hotspot", isActive: phoneBridge.isHotspotActive) {
                        phoneBridge.toggleHotspot()
                    }
                    quickDeckButton(icon: "iphone.badge.play", title: "Mirror", isActive: phoneBridge.isMirroringActive) {
                        if phoneBridge.isMirroringActive {
                            phoneBridge.stopScreenMirroring()
                        } else {
                            phoneBridge.startScreenMirroring()
                        }
                    }
                    quickDeckButton(icon: "bell.slash.fill", title: "Silent", isActive: phoneBridge.isSilentModeActive) {
                        phoneBridge.toggleSilentMode()
                    }
                    quickDeckButton(icon: "moon.fill", title: "DND", isActive: phoneBridge.isDNDActive) {
                        phoneBridge.toggleDND()
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) {
                coordinator.currentView = .phoneBridge
            }
        }
    }

    private func quickDeckButton(icon: String, title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.7))
                .frame(width: 24, height: 24)
                .background(Circle().fill(isActive ? Color.accentColor : Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .help(title)
    }

    // MARK: - Helpers

    private func timeBadge(for date: Date) -> String {
        let diff = Int(date.timeIntervalSinceNow / 60)
        if diff <= 0 {
            return "Now"
        } else if diff < 60 {
            return "In \(diff)m"
        } else {
            let hours = diff / 60
            return "In \(hours)h"
        }
    }

    private func eventTimeString(_ event: EventModel) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: event.start)) - \(formatter.string(from: event.end))"
    }

    private func waveformBar(at index: Int) -> some View {
        let bandValue = Double(spectrum.bands[safe: index] ?? 0.3)
        let height = CGFloat(4.0 + bandValue * 8.0)
        return RoundedRectangle(cornerRadius: 1)
            .fill(Color.accentColor)
            .frame(width: 2, height: height)
    }

    private func weatherConditionIcon(_ cond: AmbientWeatherCondition) -> String {
        return cond.iconName
    }

    private func weatherConditionColor(_ cond: AmbientWeatherCondition) -> Color {
        switch cond {
        case .sunny: return .yellow
        case .rainy: return .cyan
        case .cloudy: return .gray
        case .clear: return .blue
        }
    }

    private func weatherConditionName(_ cond: AmbientWeatherCondition) -> String {
        switch cond {
        case .sunny: return "Clear Skies"
        case .rainy: return "Precipitation"
        case .cloudy: return "Overcast"
        case .clear: return "Clear Skies"
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

