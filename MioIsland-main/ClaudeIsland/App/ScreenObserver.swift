//
//  ScreenObserver.swift
//  ClaudeIsland
//
//  Monitors screen configuration changes
//

import AppKit

class ScreenObserver {
    private var observer: Any?
    private let onScreenChange: () -> Void

    init(onScreenChange: @escaping () -> Void) {
        self.onScreenChange = onScreenChange
        startObserving()
    }

    deinit {
        stopObserving()
    }

    private func startObserving() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The notification queue is `.main`, so the callback
            // runs on the main thread at runtime. Swift's strict
            // concurrency checker doesn't know that statically,
            // so we state-of-fact it via MainActor.assumeIsolated
            // before touching the MainActor-isolated store.
            MainActor.assumeIsolated {
                let store = NotchCustomizationStore.shared
                if store.isEditing {
                    // External monitor plug/unplug during live edit
                    // auto-cancels the session, restoring the draft
                    // origin. The user can re-enter live edit mode
                    // on the new active screen.
                    store.cancelEdit()
                }
                self?.onScreenChange()
            }
        }
    }

    private func stopObserving() {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
