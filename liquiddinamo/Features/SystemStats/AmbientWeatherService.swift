//
//  AmbientWeatherService.swift
//  LiquidDynamo
//
//  Provides ambient weather awareness for liquid glass rendering:
//  - Rain expected -> subtle droplet ripple animation near the notch
//  - Sunny -> brighter reflections and specular caustics
//  - Cloudy -> softer glass appearance and diffused blur
//  Never interferes with mouse interaction.
//

import AppKit
import Combine
import Foundation
import SwiftUI

public enum AmbientWeatherCondition: String, Codable, CaseIterable {
    case sunny = "Sunny"
    case cloudy = "Cloudy"
    case rainy = "Rainy"
    case clear = "Clear"

    public var iconName: String {
        switch self {
        case .sunny: return "sun.max.fill"
        case .cloudy: return "cloud.fill"
        case .rainy: return "cloud.rain.fill"
        case .clear: return "moon.stars.fill"
        }
    }
}

@MainActor
public final class AmbientWeatherService: ObservableObject {
    public static let shared = AmbientWeatherService()

    @Published public private(set) var condition: AmbientWeatherCondition = .sunny
    @Published public private(set) var specularGlareIntensity: Double = 1.0
    @Published public private(set) var glassDiffusionSoftness: Double = 1.0
    @Published public private(set) var rainDropletRipplePhase: Double = 0.0

    private var rippleTimer: Timer?

    private init() {
        determineInitialCondition()
        updateRippleAnimationState()
    }

    private func determineInitialCondition() {
        // Derive ambient heuristic based on system time and solar cycle
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 6 && hour < 18 {
            self.condition = .sunny
            self.specularGlareIntensity = 1.25
            self.glassDiffusionSoftness = 0.90
        } else {
            self.condition = .clear
            self.specularGlareIntensity = 0.85
            self.glassDiffusionSoftness = 1.10
        }
    }

    public func setCondition(_ newCondition: AmbientWeatherCondition) {
        self.condition = newCondition
        updateRippleAnimationState()
        switch newCondition {
        case .sunny:
            specularGlareIntensity = 1.35
            glassDiffusionSoftness = 0.85
        case .cloudy:
            specularGlareIntensity = 0.70
            glassDiffusionSoftness = 1.40
        case .rainy:
            specularGlareIntensity = 1.10
            glassDiffusionSoftness = 1.15
        case .clear:
            specularGlareIntensity = 0.90
            glassDiffusionSoftness = 1.00
        }
    }

    private func updateRippleAnimationState() {
        if condition == .rainy {
            guard rippleTimer == nil else { return }
            let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self, self.condition == .rainy else { return }
                    self.rainDropletRipplePhase = (self.rainDropletRipplePhase + 0.12).truncatingRemainder(dividingBy: .pi * 2)
                }
            }
            timer.tolerance = 0.01
            rippleTimer = timer
        } else {
            rippleTimer?.invalidate()
            rippleTimer = nil
        }
    }
}
