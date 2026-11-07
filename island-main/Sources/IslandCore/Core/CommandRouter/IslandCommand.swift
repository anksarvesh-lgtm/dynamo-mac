import Foundation

public enum MediaCommand: Equatable, Sendable {
    case togglePlayPause, play, pause, next, previous
    case seek(to: TimeInterval)
}

public enum TimerCommand: Equatable, Sendable {
    case start(duration: TimeInterval, label: String)
    case pause(UUID), resume(UUID), reset(UUID), stop(UUID)
}

public enum DownloadCommand: Equatable, Sendable {
    case cancel(id: String), pause(id: String), resume(id: String)
    case reveal(URL), open(URL)
}

public enum IslandUICommand: Equatable, Sendable {
    case expand, collapse, toggleSearch, presentTransient(seconds: TimeInterval)
    case select(activityID: String?), selectNext, dismiss(activityID: String)
}

/// Every user-visible action flows through one typed command. Views and AI never call services directly.
public enum IslandCommand: Equatable, Sendable {
    case media(MediaCommand, sourceBundleID: String?)
    case timer(TimerCommand)
    case download(DownloadCommand)
    case ui(IslandUICommand)
    case openURL(URL)
    case revealFile(URL)
    case openFile(URL)
    case launchApplication(URL)
    case action(AppAction)
    case openSettings

    public var safety: SafetyLevel {
        switch self {
        case .action(let a): a.safety
        default: .safe
        }
    }
}
