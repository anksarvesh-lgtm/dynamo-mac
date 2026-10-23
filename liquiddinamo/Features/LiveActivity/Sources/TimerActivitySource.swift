//
//  TimerActivitySource.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import Combine
import Foundation
import SwiftUI

/// Emits LiveActivity events for Timers and Pomodoro sessions with dynamic progress ring support.
@MainActor
public final class TimerActivitySource: ObservableObject, LiveActivitySource {
    public let identifier: String = "timer"

    private let subject = PassthroughSubject<LiveActivity, Never>()
    public var activityPublisher: AnyPublisher<LiveActivity, Never> {
        subject.eraseToAnyPublisher()
    }

    public enum SessionType {
        case pomodoroFocus
        case pomodoroBreak
        case customTimer(name: String)

        var title: String {
            switch self {
            case .pomodoroFocus:
                return String(localized: "Focus Session")
            case .pomodoroBreak:
                return String(localized: "Break Time")
            case .customTimer(let name):
                return name
            }
        }

        var iconName: String {
            switch self {
            case .pomodoroFocus:
                return "timer"
            case .pomodoroBreak:
                return "cup.and.saucer.fill"
            case .customTimer:
                return "stopwatch.fill"
            }
        }
    }

    @Published public private(set) var sessionType: SessionType = .pomodoroFocus
    @Published public private(set) var totalDuration: TimeInterval = 25 * 60
    @Published public private(set) var remainingSeconds: TimeInterval = 25 * 60
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var isPaused: Bool = false

    private var tickerTask: Task<Void, Never>?
    private var isStarted = false

    public static let shared = TimerActivitySource()

    private init() {}

    public func start() {
        guard !isStarted else { return }
        isStarted = true
    }

    public func stop() {
        stopTimer()
        isStarted = false
    }

    // MARK: - Control API

    public func startPomodoro(focusMinutes: Double = 25) {
        startSession(type: .pomodoroFocus, duration: focusMinutes * 60)
    }

    public func startBreak(breakMinutes: Double = 5) {
        startSession(type: .pomodoroBreak, duration: breakMinutes * 60)
    }

    public func startTimer(seconds: TimeInterval, title: String = "Timer") {
        startSession(type: .customTimer(name: title), duration: seconds)
    }

    public func startSession(type: SessionType, duration: TimeInterval) {
        tickerTask?.cancel()
        self.sessionType = type
        self.totalDuration = duration
        self.remainingSeconds = duration
        self.isRunning = true
        self.isPaused = false

        emitOngoingProgress()
        startTicker()
    }

    public func pauseTimer() {
        guard isRunning && !isPaused else { return }
        isPaused = true
        tickerTask?.cancel()
        tickerTask = nil
        emitOngoingProgress()
    }

    public func resumeTimer() {
        guard isRunning && isPaused else { return }
        isPaused = false
        emitOngoingProgress()
        startTicker()
    }

    public func stopTimer() {
        tickerTask?.cancel()
        tickerTask = nil
        isRunning = false
        isPaused = false
        // Dismiss the ongoing activity
        LiveActivityCenter.shared.dismissOngoing()
    }

    // MARK: - Ticker Loop

    private func startTicker() {
        tickerTask?.cancel()
        tickerTask = Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self = self, self.isRunning, !self.isPaused else { break }

                if self.remainingSeconds > 1 {
                    self.remainingSeconds -= 1
                    self.emitOngoingProgress()
                } else {
                    self.remainingSeconds = 0
                    self.isRunning = false
                    self.emitCompletedAlert()
                    break
                }
            }
        }
    }

    // MARK: - Activity Emission

    private func emitOngoingProgress() {
        let progress = totalDuration > 0 ? (totalDuration - remainingSeconds) / totalDuration : 0
        let minutes = Int(remainingSeconds) / 60
        let seconds = Int(remainingSeconds) % 60
        let timeString = String(format: "%02d:%02d", minutes, seconds)
        let subtitle = isPaused ? String(localized: "Paused · \(timeString)") : timeString

        let activity = LiveActivity(
            id: "timer_ongoing",
            source: identifier,
            kind: .ongoing,
            priority: LiveActivityPriority.alert,
            tint: sessionType.iconName == "timer" ? .orange : .cyan,
            duration: nil, // ongoing
            coalescingKey: "timer_session",
            payload: LiveActivityPayload(
                title: sessionType.title,
                subtitle: subtitle,
                iconName: sessionType.iconName,
                value: progress,
                progressTotal: totalDuration,
                progressCurrent: totalDuration - remainingSeconds,
                actionTitle: isPaused ? String(localized: "Resume") : String(localized: "Pause"),
                action: { [weak self] in
                    if self?.isPaused == true {
                        self?.resumeTimer()
                    } else {
                        self?.pauseTimer()
                    }
                },
                secondaryActionTitle: String(localized: "Stop"),
                secondaryAction: { [weak self] in
                    self?.stopTimer()
                }
            ),
            pauseDismissalOnHover: true
        )
        subject.send(activity)
    }

    private func emitCompletedAlert() {
        let title = sessionType.title
        let activity = LiveActivity(
            id: "timer_completed",
            source: identifier,
            kind: .alert,
            priority: LiveActivityPriority.critical,
            tint: LiveActivitySeverity.critical.color,
            duration: 6.0,
            coalescingKey: "timer_completed",
            payload: LiveActivityPayload(
                title: String(localized: "Time's Up!"),
                subtitle: title,
                iconName: "bell.badge.fill",
                body: String(localized: "\(title) has ended."),
                actionTitle: String(localized: "Dismiss"),
                action: { [weak self] in
                    self?.stopTimer()
                }
            ),
            pauseDismissalOnHover: true
        )
        subject.send(activity)
        NSSound.beep()
    }
}
