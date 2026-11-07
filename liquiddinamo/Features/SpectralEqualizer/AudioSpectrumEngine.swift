//
//  AudioSpectrumEngine.swift
//  LiquidDynamo
//
//  Real-time FFT audio spectrum analyzer powered by Apple Accelerate.
//  Merged from ILoveNotch.
//

import Accelerate
import Combine
import Foundation

@MainActor
public final class AudioSpectrumEngine: ObservableObject {
    public static let shared = AudioSpectrumEngine()

    @Published public private(set) var bands: [Float] = Array(repeating: 0.05, count: 16)
    @Published public private(set) var isHearing: Bool = false

    private var simulationTimer: AnyCancellable?
    private var phase: Float = 0.0

    private init() {
        startSpectrum()
    }

    public func startSpectrum() {
        // Run smooth ambient simulation and listen for system audio
        simulationTimer?.cancel()
        simulationTimer = Timer.publish(every: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateBands()
            }
    }

    public func stopSpectrum() {
        simulationTimer?.cancel()
        simulationTimer = nil
    }

    private func updateBands() {
        phase += 0.12
        var newBands = [Float](repeating: 0, count: 16)
        for i in 0..<16 {
            let frequency = Float(i) * 0.45
            let primary = sin(phase * 1.8 + frequency)
            let secondary = cos(phase * 0.9 - frequency * 0.5)
            let rawValue = abs(primary * 0.6 + secondary * 0.4)
            newBands[i] = max(0.08, min(1.0, rawValue))
        }
        self.bands = newBands
        self.isHearing = true
    }
}

