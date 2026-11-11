// SPDX-License-Identifier: MIT
import AppKit
import Combine
import Foundation

@MainActor
public final class IslandService: ObservableObject {
    public static let shared = IslandService()

    private enum Keys {
        static let isIslandEnabled = "maclink_island_enabled"
        static let keepAwakeEnabled = "maclink_island_keepawake_enabled"
        static let devicesSlot1Enabled = "maclink_island_devices_slot1_enabled"
        static let clipboardHistoryEnabled = "maclink_island_clipboard_enabled"
    }

    @Published public var isIslandEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isIslandEnabled, forKey: Keys.isIslandEnabled)
            syncOverlayWindow()
        }
    }

    @Published public var keepAwakeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(keepAwakeEnabled, forKey: Keys.keepAwakeEnabled)
        }
    }

    @Published public var devicesSlot1Enabled: Bool {
        didSet {
            UserDefaults.standard.set(devicesSlot1Enabled, forKey: Keys.devicesSlot1Enabled)
        }
    }

    @Published public var clipboardHistoryEnabled: Bool {
        didSet {
            UserDefaults.standard.set(clipboardHistoryEnabled, forKey: Keys.clipboardHistoryEnabled)
        }
    }

    private var overlayWindow: IslandOverlayWindow?

    public init() {
        // Strict Hard Rule 4: Island ships OFF by default.
        let enabled = UserDefaults.standard.bool(forKey: Keys.isIslandEnabled)
        self.isIslandEnabled = enabled

        self.keepAwakeEnabled = UserDefaults.standard.object(forKey: Keys.keepAwakeEnabled) != nil
            ? UserDefaults.standard.bool(forKey: Keys.keepAwakeEnabled)
            : true

        self.devicesSlot1Enabled = UserDefaults.standard.object(forKey: Keys.devicesSlot1Enabled) != nil
            ? UserDefaults.standard.bool(forKey: Keys.devicesSlot1Enabled)
            : true

        self.clipboardHistoryEnabled = UserDefaults.standard.object(forKey: Keys.clipboardHistoryEnabled) != nil
            ? UserDefaults.standard.bool(forKey: Keys.clipboardHistoryEnabled)
            : true

        if enabled {
            syncOverlayWindow()
        }
    }

    public func syncOverlayWindow() {
        if isIslandEnabled {
            if overlayWindow == nil {
                let win = IslandOverlayWindow()
                win.orderFront(nil)
                overlayWindow = win
            }
        } else {
            if let win = overlayWindow {
                win.close()
                overlayWindow = nil
            }
            if KeepAwakeManager.shared.isActive {
                KeepAwakeManager.shared.stop()
            }
        }
    }
}
