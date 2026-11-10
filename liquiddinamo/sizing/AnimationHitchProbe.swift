//
//  AnimationHitchProbe.swift
//  LiquidDynamo
//
//  Real-time CADisplayLink frame delivery measurement and hitch monitoring for 120Hz ProMotion displays.
//  Adopted from isleta's zero-hitch architecture.
//

import AppKit
import Foundation
import QuartzCore

@MainActor
public final class AnimationHitchProbe: NSObject {
    public static let shared = AnimationHitchProbe()

    public static let isRequested = ProcessInfo.processInfo.arguments.contains("--hitch-probe")

    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    public private(set) var droppedFrameCount: Int = 0

    private override init() {
        super.init()
    }

    public func attach(to window: NSWindow) {
        guard Self.isRequested, link == nil, let view = window.contentView else { return }
        let displayLink = view.displayLink(target: self, selector: #selector(displayLinkTick))
        displayLink.add(to: .main, forMode: .common)
        self.link = displayLink
        print("==> [ProMotion] AnimationHitchProbe attached to window #\(window.windowNumber)")
    }

    public func stop() {
        link?.invalidate()
        link = nil
        lastTimestamp = nil
    }

    @objc private func displayLinkTick(_ sender: CADisplayLink) {
        let current = sender.timestamp
        defer { lastTimestamp = current }

        guard let last = lastTimestamp else { return }
        let delta = current - last
        let targetInterval = sender.targetTimestamp - sender.timestamp
        let frameBudget = targetInterval > 0 ? targetInterval : (1.0 / 120.0)

        // If the gap exceeds 1.5x frame budget, a frame was dropped
        if delta > (frameBudget * 1.5) {
            let dropped = Int(round(delta / frameBudget)) - 1
            if dropped > 0 {
                droppedFrameCount += dropped
                print("⚠️ [ProMotion Hitch] Dropped \(dropped) frame(s) — Delta: \(String(format: "%.2f", delta * 1000))ms (Budget: \(String(format: "%.2f", frameBudget * 1000))ms)")
            }
        }
    }
}

