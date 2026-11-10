//
//  BetterDisplayBridge.swift
//  LiquidDynamo
//
//  Integration bridge with BetterDisplay for hardware DDC brightness and volume control on external monitors.
//  Adopted from Atoll's BetterDisplay integration.
//

import AppKit
import Combine
import Foundation

@MainActor
public final class BetterDisplayBridge: ObservableObject {
    public static let shared = BetterDisplayBridge()

    @Published public private(set) var isBetterDisplayRunning: Bool = false
    @Published public private(set) var externalDisplayBrightness: Double = 0.8
    @Published public private(set) var externalDisplayVolume: Double = 0.5

    private init() {
        checkAppLiveness()
        observeNotifications()
    }

    public func checkAppLiveness() {
        let apps = NSWorkspace.shared.runningApplications
        isBetterDisplayRunning = apps.contains { $0.bundleIdentifier == "pro.betterdisplay.BetterDisplay" }
    }

    private func observeNotifications() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("pro.betterdisplay.BetterDisplay.OSD"),
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let self = self, let userInfo = notif.userInfo, let jsonString = userInfo["json"] as? String else { return }
            self.parseBetterDisplayJSON(jsonString)
        }
    }

    private func parseBetterDisplayJSON(_ json: String) {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let val = dict["value"] as? Double, let maxVal = dict["maxValue"] as? Double, maxVal > 0 {
            let normalized = min(max(val / maxVal, 0.0), 1.0)
            if let target = dict["controlTarget"] as? String {
                if target.contains("brightness") {
                    self.externalDisplayBrightness = normalized
                } else if target.contains("volume") {
                    self.externalDisplayVolume = normalized
                }
            }
        }
    }

    /// Sends a DDC brightness change request to BetterDisplay
    public func setBrightness(_ value: Double) {
        guard isBetterDisplayRunning else { return }
        let payload: [String: Any] = [
            "commands": ["setBrightness"],
            "parameters": ["value": "\(Int(value * 100))"]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let jsonString = String(data: data, encoding: .utf8) {
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("pro.betterdisplay.BetterDisplay.command"),
                object: nil,
                userInfo: ["json": jsonString],
                deliverImmediately: true
            )
        }
    }
}

