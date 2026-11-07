import AppKit
import IslandCore

/// Routes typed `IslandCommand`s to the subsystem that owns them. Handlers are registered by the
/// composition root, so views and providers never reference each other directly.
@MainActor
final class CommandRouter {
    var media: ((MediaCommand, String?) -> Void)?
    var timer: ((TimerCommand) -> Void)?
    var download: ((DownloadCommand) -> Void)?
    var ui: ((IslandUICommand) -> Void)?
    var action: ((AppAction, ActionOrigin) -> Void)?
    var openSettings: (() -> Void)?
    private(set) var lastCommand: IslandCommand?

    func perform(_ command: IslandCommand, origin: ActionOrigin = .user) {
        lastCommand = command
        guard PermissionPolicy.isAllowed(command.safety, origin: origin, userConfirmed: origin == .user) else {
            NSLog("Island: blocked command %@ from %@", String(describing: command), origin.rawValue)
            return
        }
        switch command {
        case .media(let c, let source): media?(c, source)
        case .timer(let c): timer?(c)
        case .download(let c): download?(c)
        case .ui(let c): ui?(c)
        case .action(let a): action?(a, origin)
        case .openSettings: openSettings?()
        case .openURL(let url):
            guard let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) else { return }
            NSWorkspace.shared.open(url)
        case .revealFile(let url): NSWorkspace.shared.activateFileViewerSelecting([url])
        case .openFile(let url): NSWorkspace.shared.open(url)
        case .launchApplication(let url):
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error { NSLog("Island: failed to open app: %@", error.localizedDescription) }
            }
        }
    }
}
