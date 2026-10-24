//
//  SettingsHydrationView.swift
//  LiquidDynamo
//
//  Hydration Reminder Control Center: Character-based water reminder system
//  featuring animated liquid mascot "Hydro", customizable cadence, and notch alerts.
//

import AppKit
import Defaults
import SwiftUI

public struct SettingsHydrationView: View {
    @Default(.hydrationEnabled) private var hydrationEnabled
    @Default(.hydrationIntervalMinutes) private var intervalMinutes
    @Default(.hydrationSoundEnabled) private var soundEnabled
    @Default(.hydrationAnimationEnabled) private var animationEnabled
    @Default(.hydrationCharacterStyle) private var characterStyle

    @State private var mascotBob: CGFloat = 0.0
    @State private var mascotSmile: Bool = true
    @State private var customMinutes: Double = 45.0

    let intervalPresets: [Int] = [30, 45, 60, 120]

    public init() {}

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hydration System")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("Character-driven water breaks with fluid Dynamic Island reminders")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $hydrationEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                // Coming Soon Health & Focus Suite Card
                comingSoonRemindersCard
                    .padding(.horizontal, 24)

                // Mascot Hero Card
                mascotHeroCard
                    .padding(.horizontal, 24)

                // Cadence & Interval Card
                intervalCard
                    .padding(.horizontal, 24)

                // Sound & Animation Settings
                preferencesCard
                    .padding(.horizontal, 24)

                Spacer(minLength: 20)
            }
        }
    }

    // MARK: - Mascot Hero Preview Card
    private var mascotHeroCard: some View {
        HStack(spacing: 24) {
            // Animated Liquid Water Mascot
            ZStack {
                // Ambient Water Aura
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.cyan.opacity(0.4), Color.blue.opacity(0.15), Color.clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 70
                        )
                    )
                    .frame(width: 140, height: 140)

                // Mascot Body (Liquid Droplet)
                ZStack {
                    // Outer droplet shape
                    Path { path in
                        path.move(to: CGPoint(x: 50, y: 15))
                        path.addCurve(to: CGPoint(x: 88, y: 65), control1: CGPoint(x: 75, y: 35), control2: CGPoint(x: 88, y: 50))
                        path.addCurve(to: CGPoint(x: 50, y: 88), control1: CGPoint(x: 88, y: 80), control2: CGPoint(x: 70, y: 88))
                        path.addCurve(to: CGPoint(x: 12, y: 65), control1: CGPoint(x: 30, y: 88), control2: CGPoint(x: 12, y: 80))
                        path.addCurve(to: CGPoint(x: 50, y: 15), control1: CGPoint(x: 12, y: 50), control2: CGPoint(x: 25, y: 35))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.35, green: 0.85, blue: 1.0),
                                Color(red: 0.15, green: 0.55, blue: 0.95)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 100, height: 100)
                    .overlay(
                        // Specular Highlight
                        Ellipse()
                            .fill(Color.white.opacity(0.6))
                            .frame(width: 22, height: 10)
                            .rotationEffect(.degrees(-30))
                            .offset(x: -18, y: -24)
                    )

                    // Cute Mascot Face
                    HStack(spacing: 16) {
                        Circle().fill(Color.black.opacity(0.75)).frame(width: 7, height: 7)
                            .overlay(Circle().fill(Color.white).frame(width: 2, height: 2).offset(x: -1, y: -1))
                        Circle().fill(Color.black.opacity(0.75)).frame(width: 7, height: 7)
                            .overlay(Circle().fill(Color.white).frame(width: 2, height: 2).offset(x: -1, y: -1))
                    }
                    .offset(y: 4)

                    // Smile
                    Path { p in
                        p.move(to: CGPoint(x: 43, y: 64))
                        p.addQuadCurve(to: CGPoint(x: 57, y: 64), control: CGPoint(x: 50, y: 70))
                    }
                    .stroke(Color.black.opacity(0.75), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

                    // Translucent Water Glass Mascot is Holding
                    ZStack {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.white.opacity(0.35))
                            .frame(width: 16, height: 22)
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white.opacity(0.8), lineWidth: 0.8))

                        // Water level inside glass
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.cyan.opacity(0.8))
                            .frame(width: 12, height: 14)
                            .offset(y: 2)
                    }
                    .offset(x: 34, y: 14)
                }
                .offset(y: mascotBob)
                .animation(
                    Animation.easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                    value: mascotBob
                )
            }
            .frame(width: 130, height: 130)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Meet \(characterStyle)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Active Mascot")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.cyan.opacity(0.25)))
                        .foregroundStyle(Color.cyan)
                }

                Text("Hydro emerges from your notch at set intervals to encourage regular hydration during long computing sessions.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button {
                        DynamicIslandHub.shared.triggerHydrationAlert(
                            title: "Time for Water!",
                            message: "\(characterStyle) recommends taking a refreshing sip."
                        )
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "drop.fill")
                                .font(.system(size: 11))
                            Text("Test Reminder in Notch")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(LinearGradient(colors: [Color.cyan.opacity(0.3), Color.blue.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .overlay(Capsule().strokeBorder(Color.cyan.opacity(0.5), lineWidth: 0.8))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [Color.cyan.opacity(0.4), Color.white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
        )
        .onAppear {
            mascotBob = -5.0
        }
    }

    // MARK: - Interval Selection Card
    private var intervalCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Reminder Frequency")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            HStack(spacing: 10) {
                ForEach(intervalPresets, id: \.self) { mins in
                    let isSelected = intervalMinutes == mins
                    Button {
                        intervalMinutes = mins
                    } label: {
                        Text(labelForMinutes(mins))
                            .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(isSelected ? Color.cyan.opacity(0.25) : Color.white.opacity(0.06))
                                    .overlay(
                                        Capsule().strokeBorder(isSelected ? Color.cyan.opacity(0.6) : Color.white.opacity(0.1), lineWidth: 0.8)
                                    )
                            )
                            .foregroundStyle(isSelected ? Color.cyan : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().opacity(0.2)

            // Custom Slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Custom Duration")
                        .font(.system(size: 12, design: .rounded))
                    Spacer()
                    Text("\(intervalMinutes) Minutes")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.cyan)
                }

                Slider(value: Binding(
                    get: { Double(intervalMinutes) },
                    set: { intervalMinutes = Int($0) }
                ), in: 15...180, step: 5)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        )
    }

    // MARK: - Preferences Card
    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Behavior & Aesthetics")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Toggle("Play subtle water droplet chime on reminder", isOn: $soundEnabled)
                .font(.system(size: 12, design: .rounded))

            Toggle("Enable fluid water splash animation inside Notch", isOn: $animationEnabled)
                .font(.system(size: 12, design: .rounded))

            Divider().opacity(0.2)

            HStack {
                Text("Character Style")
                    .font(.system(size: 12, design: .rounded))
                Spacer()
                Picker("", selection: $characterStyle) {
                    Text("Hydro Drop").tag("Hydro")
                    Text("Aqua Bubble").tag("Aqua")
                    Text("Liquid Glug").tag("Glug")
                }
                .labelsHidden()
                .frame(width: 140)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        )
    }

    private func labelForMinutes(_ mins: Int) -> String {
        switch mins {
        case 30: return "30 min"
        case 45: return "45 min"
        case 60: return "1 hour"
        case 120: return "2 hours"
        default: return "\(mins) min"
        }
    }

    // MARK: - Coming Soon Suite Card
    private var comingSoonRemindersCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Wellness & Health Reminders", systemImage: "sparkles")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                Text("COMING SOON")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.cyan.opacity(0.18))
                    .foregroundStyle(Color.cyan)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.cyan.opacity(0.4), lineWidth: 0.8))
            }

            Text("Next-generation physical wellness monitors integrating directly with your Dynamic Island.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)

            Divider().opacity(0.2)

            HStack(spacing: 12) {
                // Water Reminder Box
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.cyan)
                        Text("Water Reminder")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    }

                    Text("Intelligent hydration cadence, drink logging, and animated water droplet mascot alerts.")
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)

                    HStack(spacing: 4) {
                        Circle().fill(Color.cyan).frame(width: 5, height: 5)
                        Text("Coming Soon")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.cyan)
                    }
                    .padding(.top, 2)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.cyan.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.cyan.opacity(0.25), lineWidth: 0.8))
                )

                // Break Reminder Box
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.orange)
                        Text("Break Reminder")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    }

                    Text("20-20-20 screen rest, posture realignment cues, and gentle stretch prompts.")
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)

                    HStack(spacing: 4) {
                        Circle().fill(Color.orange).frame(width: 5, height: 5)
                        Text("Coming Soon")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.orange)
                    }
                    .padding(.top, 2)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.orange.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.8))
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        )
    }
}
