//
//  MediaLiveActivityView.swift
//  LiquidDynamo
//
//  Step 3 Complex View Migration: Now-Playing Media Controls.
//  Provides both compact top band wing presentation and organic below-notch blooming droplet presentation.
//

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

public struct MediaLiveActivityView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var motion = IslandMotion.shared

    public var isCompactWing: Bool = false
    public var isLeadingWing: Bool = true
    public var onDismiss: () -> Void = {}

    @State private var isScrubbing: Bool = false
    @State private var scrubProgress: Double = 0.0

    public init(
        isCompactWing: Bool = false,
        isLeadingWing: Bool = true,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.isCompactWing = isCompactWing
        self.isLeadingWing = isLeadingWing
        self.onDismiss = onDismiss
    }

    private var currentProgress: Double {
        if isScrubbing { return scrubProgress }
        guard musicManager.songDuration > 0 else { return 0.0 }
        return min(max(musicManager.elapsedTime / musicManager.songDuration, 0.0), 1.0)
    }

    private var tintColor: Color {
        if Defaults[.playerColorTinting] {
            return Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
        }
        return Color.accentColor
    }

    public var body: some View {
        if isCompactWing {
            compactWingLayout
        } else {
            bloomingDropletLayout
        }
    }

    // MARK: - 1. Compact Wing Presentation (Top Band)

    private var compactWingLayout: some View {
        HStack(spacing: 6) {
            if isLeadingWing {
                // Mini Album Art or Music Note
                if let image = musicManager.albumArt as NSImage? {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 14, height: 14)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(tintColor)
                }

                Text(musicManager.songTitle.isEmpty ? "Now Playing" : musicManager.songTitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            } else {
                // Live Waveform / Visualizer Bars or Artist Name
                HStack(spacing: 2) {
                    ForEach(0..<4) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(tintColor)
                            .frame(
                                width: 2.5,
                                height: musicManager.isPlaying ? CGFloat([8, 14, 11, 6][i]) : 3
                            )
                            .animation(
                                musicManager.isPlaying
                                ? .easeInOut(duration: 0.35).repeatForever().delay(Double(i) * 0.08)
                                : .default,
                                value: musicManager.isPlaying
                            )
                    }
                }
                .frame(width: 18, height: 14)
            }
        }
        .padding(.horizontal, 6)
        .avoidsNotch(id: isLeadingWing ? "MediaWingL" : "MediaWingR")
    }

    // MARK: - 2. Blooming Droplet Presentation (Below Notch)

    private var bloomingDropletLayout: some View {
        VStack(spacing: 8) {
            // Header Row: Album Art + Song & Artist + Waveform
            HStack(spacing: 12) {
                // Album Art with organic rounded corners and soft glow
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(tintColor.opacity(0.2))
                        .frame(width: 38, height: 38)

                    Image(nsImage: musicManager.albumArt)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 38, height: 38)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .shadow(color: tintColor.opacity(0.35), radius: 4, y: 2)

                // Track Metadata
                VStack(alignment: .leading, spacing: 2) {
                    Text(musicManager.songTitle.isEmpty ? "No Song Playing" : musicManager.songTitle)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(musicManager.artistName.isEmpty ? "Liquid Island" : musicManager.artistName)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                // Live Equalizer Indicator
                HStack(spacing: 2.5) {
                    ForEach(0..<5) { idx in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(tintColor)
                            .frame(
                                width: 3,
                                height: musicManager.isPlaying ? CGFloat([10, 16, 12, 18, 8][idx]) : 4
                            )
                            .animation(
                                musicManager.isPlaying
                                ? .easeInOut(duration: 0.4).repeatForever().delay(Double(idx) * 0.07)
                                : .default,
                                value: musicManager.isPlaying
                            )
                    }
                }
                .frame(width: 26, height: 20)
            }

            // Scrubber Bar & Timestamps
            if musicManager.songDuration > 0 {
                VStack(spacing: 3) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            // Track
                            Capsule()
                                .fill(Color.white.opacity(0.18))
                                .frame(height: 4)

                            // Fill
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [tintColor, tintColor.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(4, geo.size.width * CGFloat(currentProgress)), height: 4)
                        }
                        .frame(maxHeight: .infinity, alignment: .center)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    isScrubbing = true
                                    scrubProgress = min(max(Double(value.location.x / geo.size.width), 0.0), 1.0)
                                }
                                .onEnded { _ in
                                    let targetSec = scrubProgress * musicManager.songDuration
                                    musicManager.elapsedTime = targetSec
                                    isScrubbing = false
                                }
                        )
                    }
                    .frame(height: 10)

                    // Time labels
                    HStack {
                        Text(formatTime(musicManager.elapsedTime))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("-\(formatTime(max(0, musicManager.songDuration - musicManager.elapsedTime)))")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Playback Controls Row
            HStack(spacing: 24) {
                // Previous Track
                Button(action: {
                    musicManager.previousTrack()
                    triggerHaptic()
                }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.plain)

                // Play / Pause
                Button(action: {
                    musicManager.togglePlay()
                    triggerHaptic()
                }) {
                    Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(tintColor.opacity(0.35)))
                }
                .buttonStyle(.plain)

                // Next Track
                Button(action: {
                    musicManager.nextTrack()
                    triggerHaptic()
                }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .frame(width: 290)
        .avoidsNotch(id: "MediaBloomingDroplet")
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        let m = s / 60
        let remS = s % 60
        return String(format: "%d:%02d", m, remS)
    }

    private func triggerHaptic() {
        if Defaults[.enableHaptics] {
            NSHapticFeedbackManager.defaultPerformer.perform(
                .alignment,
                performanceTime: .default
            )
        }
    }
}
