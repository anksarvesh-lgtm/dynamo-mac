//
//  WeatherPrecipitationEngine.swift
//  LiquidDynamo
//
//  Particle weather physics engine rendering rain and snow droplets colliding
//  against the bottom liquid glass lip. Merged from Isleta.
//

import Combine
import SwiftUI

public enum PrecipitationType {
    case none
    case rain
    case snow
}

public struct PrecipitationDrop: Identifiable {
    public let id = UUID()
    public var x: CGFloat
    public var y: CGFloat
    public var speed: CGFloat
    public var length: CGFloat
    public var opacity: Double
}

@MainActor
public final class WeatherPrecipitationEngine: ObservableObject {
    public static let shared = WeatherPrecipitationEngine()

    @Published public var currentType: PrecipitationType = .rain
    @Published public private(set) var drops: [PrecipitationDrop] = []

    private var animationTimer: AnyCancellable?
    private let maxDrops = 28

    private init() {
        startParticleLoop()
    }

    public func setPrecipitation(from weatherCondition: String) {
        let condition = weatherCondition.lowercased()
        if condition.contains("rain") || condition.contains("drizzle") || condition.contains("shower") {
            currentType = .rain
        } else if condition.contains("snow") || condition.contains("flurry") || condition.contains("blizzard") {
            currentType = .snow
        } else {
            currentType = .none
        }
    }

    public func startParticleLoop() {
        animationTimer?.cancel()
        animationTimer = Timer.publish(every: 0.04, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.advanceParticles(width: 400, height: 160)
            }
    }

    public func advanceParticles(width: CGFloat, height: CGFloat) {
        guard currentType != .none else {
            if !drops.isEmpty { drops.removeAll() }
            return
        }

        var updated = drops
        for i in 0..<updated.count {
            updated[i].y += updated[i].speed
            if updated[i].y > height {
                // Respawn at top
                updated[i].y = CGFloat.random(in: -20...0)
                updated[i].x = CGFloat.random(in: 0...width)
            }
        }

        while updated.count < maxDrops {
            let speed = currentType == .rain ? CGFloat.random(in: 6...12) : CGFloat.random(in: 1.5...3.5)
            let length = currentType == .rain ? CGFloat.random(in: 6...14) : CGFloat.random(in: 2...4)
            updated.append(
                PrecipitationDrop(
                    x: CGFloat.random(in: 0...width),
                    y: CGFloat.random(in: -40...height),
                    speed: speed,
                    length: length,
                    opacity: Double.random(in: 0.25...0.65)
                )
            )
        }

        self.drops = updated
    }
}

public struct WeatherPrecipitationView: View {
    @ObservedObject var engine = WeatherPrecipitationEngine.shared

    public init() {}

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(engine.drops) { drop in
                    if engine.currentType == .rain {
                        Rectangle()
                            .fill(LinearGradient(
                                colors: [Color.cyan.opacity(drop.opacity * 0.4), Color.white.opacity(drop.opacity)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            .frame(width: 1.2, height: drop.length)
                            .position(x: drop.x, y: drop.y)
                    } else if engine.currentType == .snow {
                        Circle()
                            .fill(Color.white.opacity(drop.opacity))
                            .frame(width: drop.length, height: drop.length)
                            .position(x: drop.x, y: drop.y)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .allowsHitTesting(false)
        }
    }
}
