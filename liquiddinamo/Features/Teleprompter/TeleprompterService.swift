//
//  TeleprompterService.swift
//  LiquidDynamo
//
//  Merged from SuperIsland: Floating camera-aligned notch teleprompter
//  supporting presentation scripts, automated scrolling, cadence control, and mirroring.
//

import Combine
import Foundation

@MainActor
public final class TeleprompterService: ObservableObject {
    public static let shared = TeleprompterService()

    @Published public var scriptText: String = """
Welcome everyone. Today I'm excited to present LiquidDynamo — the organic liquid glass dynamic island for macOS.
With integrated hardware telemetry, seamless Android file bridge, and real-time developer agent monitoring,
your MacBook notch is finally transformed into an intelligent command center.
"""
    @Published public var isScrolling: Bool = false
    @Published public var scrollSpeed: Double = 1.0 // 0.5x to 3.0x
    @Published public var scrollOffset: CGFloat = 0.0
    @Published public var isMirrored: Bool = false
    @Published public var fontSize: CGFloat = 14.0

    private var timer: AnyCancellable?

    private init() {}

    public func toggleScrolling() {
        if isScrolling {
            pauseScrolling()
        } else {
            startScrolling()
        }
    }

    public func startScrolling() {
        isScrolling = true
        timer?.cancel()
        timer = Timer.publish(every: 0.03, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, self.isScrolling else { return }
                self.scrollOffset += CGFloat(0.8 * self.scrollSpeed)
            }
    }

    public func pauseScrolling() {
        isScrolling = false
        timer?.cancel()
        timer = nil
    }

    public func resetScroll() {
        pauseScrolling()
        scrollOffset = 0.0
    }
}
