//
//  AirPodsOrbitRingView.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import SwiftUI

// MARK: - Orbit Arc Shape

public struct OrbitArcShape: Shape {
    public var progress: Double // 0.0 ... 1.0
    public var startAngle: Angle = .degrees(-90)

    public var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) / 2.0
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let endAngle = startAngle + .degrees(progress * 360.0)

        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
    }
}

// MARK: - AirPods Orbit Ring View

@MainActor
public struct AirPodsOrbitRingView: View {
    public var title: String
    public var level: Int?
    public var isCharging: Bool
    public var isReduceMotion: Bool
    public var size: CGFloat

    public init(
        title: String,
        level: Int?,
        isCharging: Bool = false,
        isReduceMotion: Bool = false,
        size: CGFloat = 84
    ) {
        self.title = title
        self.level = level
        self.isCharging = isCharging
        self.isReduceMotion = isReduceMotion
        self.size = size
    }

    private var progress: Double {
        guard let level = level else { return 0.0 }
        return Double(min(max(level, 0), 100)) / 100.0
    }

    private var arcColor: Color {
        guard let level = level else { return .gray.opacity(0.3) }
        if level <= 5 {
            return .red
        } else if level <= 15 {
            return .orange
        } else {
            return Color(red: 0.30, green: 0.85, blue: 0.45)
        }
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: (isCharging && !isReduceMotion) ? (1.0 / 30.0) : 1.0)) { timeline in
            let phase: Double = (isCharging && !isReduceMotion)
                ? ((sin(timeline.date.timeIntervalSinceReferenceDate * 3.2) + 1.0) / 2.0)
                : 0.0
            let pulseScale: CGFloat = 1.0 + CGFloat(phase) * 0.09
            let pulseOpacity: Double = 0.30 + (1.0 - phase) * 0.50

            ZStack {
                // 1. Inactive background track
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 3.5)
                    .frame(width: size, height: size)

                // 2. Charging pulse halo
                if isCharging && level != nil {
                    Circle()
                        .stroke(arcColor.opacity(pulseOpacity * 0.45), lineWidth: 5.5)
                        .frame(width: size, height: size)
                        .scaleEffect(isReduceMotion ? 1.0 : pulseScale)
                }

                // 3. Dynamic Orbit Arc
                OrbitArcShape(progress: progress)
                    .stroke(
                        arcColor,
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                    )
                    .frame(width: size, height: size)
                    .shadow(color: arcColor.opacity(0.6), radius: isCharging ? 4 : 2)

                // 4. Center Label & Charging Indicator
                VStack(spacing: 2) {
                    if let level = level {
                        HStack(spacing: 2) {
                            Text("\(level)%")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            if isCharging {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(arcColor)
                            }
                        }
                    } else {
                        Text("--")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.4))
                    }

                    Text(title)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.65))
                }
            }
        }
    }
}
