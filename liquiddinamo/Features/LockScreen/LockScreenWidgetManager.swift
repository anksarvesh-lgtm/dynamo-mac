//
//  LockScreenWidgetManager.swift
//  LiquidDynamo
//
//  Manages lock screen detection, live widgets, and smooth unlock transitions.
//  Adopted from Atoll's lock screen presentation architecture.
//

import AppKit
import Combine
import Foundation
import SwiftUI

public enum LockScreenState: String, CaseIterable, Sendable {
    case unlocked
    case locked
    case authenticating
}

@MainActor
public final class LockScreenWidgetManager: ObservableObject {
    public static let shared = LockScreenWidgetManager()

    @Published public private(set) var screenState: LockScreenState = .unlocked
    @Published public private(set) var isScreenLocked: Bool = false
    @Published public var showLockScreenWidgets: Bool = true

    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupDistributedNotificationObservers()
    }

    private func setupDistributedNotificationObservers() {
        let dnc = DistributedNotificationCenter.default()

        // 1. Screen lock notification
        dnc.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleScreenLocked()
            }
        }

        // 2. Screen unlock notification
        dnc.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleScreenUnlocked()
            }
        }
    }

    private func handleScreenLocked() {
        isScreenLocked = true
        screenState = .locked
        print("==> [LockScreen] Screen locked — activating lock-screen ambient presentation")
    }

    private func handleScreenUnlocked() {
        screenState = .authenticating
        // Provide smooth unlock settling beat
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.isScreenLocked = false
            self?.screenState = .unlocked
            print("==> [LockScreen] Screen unlocked — resuming standard Dynamic Island")
        }
    }
}

