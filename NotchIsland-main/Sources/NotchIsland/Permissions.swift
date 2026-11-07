import AppKit
import ApplicationServices
import EventKit
import Security

extension Notification.Name {
    /// Posted on the main thread after `tccutil reset`: modules drop cached "declined" state and look again.
    static let notchPermissionsReset = Notification.Name("NotchIsland.permissionsReset")
}

/// A grant the island depends on.
///
/// macOS ties every grant (Accessibility, Full Disk Access, Calendar, Automation…) to the code
/// signature of the build that asked for it. A build with a different signature fails that check:
/// the switch in System Settings stays on, the switch does nothing, and flipping it does not update
/// the stored requirement. 1.0.0 was signed ad hoc (a new signature every build) and a `swift run`
/// binary is keyed by its path, so anyone who granted something to either of those sees exactly
/// that with the signed releases. The way out is to remove the entry (`tccutil reset`) and let
/// macOS ask again; see `Permissions.repair`.
enum Permission: String, CaseIterable, Identifiable {
    case accessibility, fullDiskAccess, calendar

    var id: String { rawValue }

    /// Service name as `tccutil` wants it.
    var tccService: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .fullDiskAccess: return "SystemPolicyAllFiles"
        case .calendar: return "Calendar"
        }
    }

    var title: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .fullDiskAccess: return "Full Disk Access"
        case .calendar: return "Calendar"
        }
    }

    var purpose: String {
        switch self {
        case .accessibility: return "Swallows the hotkey so nothing else hears it; media keys in browsers."
        case .fullDiskAccess: return "Notifications: Notification Center's store is only readable with it."
        case .calendar: return "The next event and its meeting link in the shade."
        }
    }

    var pane: String {
        switch self {
        case .accessibility: return PrivacyPane.accessibility
        case .fullDiskAccess: return PrivacyPane.fullDiskAccess
        case .calendar: return PrivacyPane.calendars
        }
    }

    /// Whether macOS can ask for it with a dialog. Full Disk Access can only be added by hand.
    var hasPrompt: Bool { self != .fullDiskAccess }
}

enum Grant: Equatable {
    case granted
    case denied
    case notAsked      // macOS has never asked (Calendar only)
    case unknown       // nothing to test against yet (no notification store on this Mac)

    var isGranted: Bool { self == .granted }
}

enum Permissions {
    static let bundleID = "com.notchisland.app"

    /// What the row shows: the grant, and whether it was seen granted before and is not any more.
    struct Status: Equatable {
        var grant: Grant
        var stale: Bool
        var isGranted: Bool { grant.isGranted }
    }

    /// Running as NotchIsland.app (grants keyed by bundle id) rather than a bare `swift run` binary
    /// (grants keyed by path, which `tccutil reset <bundle id>` cannot touch).
    static var isBundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    /// Hook for the Calendar prompt, set by the owner of the live `CalendarModule`.
    static var calendarRequest: (() -> Void)?

    // MARK: Reading

    static func check(_ p: Permission) -> Grant {
        switch p {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .denied
        case .fullDiskAccess:
            switch NotificationWatcher.storeAccess() {
            case .ok: return .granted
            case .needsFullDiskAccess: return .denied
            case .missing, .failed: return .unknown
            }
        case .calendar:
            let s = EKEventStore.authorizationStatus(for: .event)
            switch s {
            case .notDetermined: return .notAsked
            case .authorized: return .granted
            default:
                if #available(macOS 14, *), s == .fullAccess { return .granted }
                return .denied
            }
        }
    }

    /// Reads a permission and remembers the answer, so a grant that disappears is reported as stale.
    static func status(_ p: Permission) -> Status {
        let grant = check(p)
        let d = UserDefaults.standard
        switch grant {
        case .granted:
            if !d.bool(forKey: grantedKey(p)) { d.set(true, forKey: grantedKey(p)) }
            if d.object(forKey: staleKey(p)) != nil { d.removeObject(forKey: staleKey(p)) }
            return Status(grant: grant, stale: false)
        case .denied:
            if d.bool(forKey: grantedKey(p)) {
                if !d.bool(forKey: staleKey(p)) { d.set(true, forKey: staleKey(p)) }
                return Status(grant: grant, stale: true)
            }
            return Status(grant: grant, stale: d.bool(forKey: staleKey(p)))
        case .notAsked, .unknown:
            return Status(grant: grant, stale: false)
        }
    }

    private static func grantedKey(_ p: Permission) -> String { "permissions.granted.\(p.rawValue)" }
    private static func staleKey(_ p: Permission) -> String { "permissions.stale.\(p.rawValue)" }
    private static let identityKey = "permissions.identity"

    // MARK: Code identity

    /// The designated requirement macOS stores with every grant, e.g.
    /// `identifier "com.notchisland.app" and certificate root = H"…"` for a release, or
    /// `cdhash H"…"` for an ad-hoc build (different after every compile).
    static let codeIdentity: String = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return "unsigned" }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return "unsigned" }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess,
              let requirement else { return "unsigned" }
        var text: CFString?
        guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text else { return "unsigned" }
        return text as String
    }()

    /// Common name of the signing certificate, if any ("NotchIsland Developer", "Developer ID Application: …").
    static let signerName: String? = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any],
              let certs = dict[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certs.first else { return nil }
        return SecCertificateCopySubjectSummary(leaf) as String?
    }()

    /// One line for Settings ▸ About: who signed this build and what that means for grants.
    static var identitySummary: String {
        if codeIdentity.contains("Developer ID Application") {
            return "Signed with \(signerName ?? "a Developer ID") · grants survive updates"
        }
        if codeIdentity.contains("certificate root") || codeIdentity.contains("certificate leaf") {
            return "Signed with the \(signerName ?? "project") certificate · grants survive updates"
        }
        if codeIdentity.contains("cdhash") {
            return "Ad-hoc signature · macOS sees every build as a new app, so grants must be made again after each build"
        }
        return "Unsigned"
    }

    // MARK: Asking and repairing

    /// Asks macOS for the permission the way that permission allows. `openPane` also brings up the
    /// System Settings list: the Accessibility dialog has its own button for that, but macOS shows
    /// no dialog while an entry (even a stale one) exists, so a click in Settings opens it anyway.
    static func ask(_ p: Permission, openPane: Bool = true) {
        switch p {
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            if openPane { PrivacyPane.open(p.pane) }
        case .fullDiskAccess:
            PrivacyPane.open(p.pane)
        case .calendar:
            if let calendarRequest {
                calendarRequest()
            } else {
                let store = EKEventStore()
                let done: (Bool, Error?) -> Void = { _, _ in _ = store }
                if #available(macOS 14, *) { store.requestFullAccessToEvents(completion: done) }
                else { store.requestAccess(to: .event, completion: done) }
            }
        }
    }

    /// Removes NotchIsland's entry for the service (or every service with `nil`) so macOS forgets
    /// a grant that belongs to an earlier build and asks again. Completion on the main thread with
    /// `tccutil`'s verdict.
    static func reset(_ p: Permission?, completion: @escaping (Bool, String) -> Void) {
        let service = p?.tccService ?? "All"
        DispatchQueue.global(qos: .userInitiated).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            proc.arguments = ["reset", service, bundleID]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            var ok = false
            var message = ""
            do {
                try proc.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                proc.waitUntilExit()
                ok = proc.terminationStatus == 0
                message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            } catch {
                message = error.localizedDescription
            }
            NSLog("NotchIsland permissions: tccutil reset %@ %@ → %@ %@", service, bundleID, ok ? "ok" : "failed", message)
            DispatchQueue.main.async {
                if ok {
                    let d = UserDefaults.standard
                    for q in Permission.allCases where p == nil || p == q {
                        d.removeObject(forKey: grantedKey(q))
                        d.removeObject(forKey: staleKey(q))
                    }
                    NotificationCenter.default.post(name: .notchPermissionsReset, object: nil)
                }
                completion(ok, message)
            }
        }
    }

    /// Reset, then ask again.
    static func repair(_ p: Permission, completion: @escaping (Bool, String) -> Void = { _, _ in }) {
        reset(p) { ok, message in
            if ok { ask(p) }
            completion(ok, message)
        }
    }

    /// Runs once per build identity, right after launch: on the first launch of a build that can
    /// repair grants, and whenever the signature changed since the last launch (an ad-hoc 1.0.0 →
    /// a signed release, or a future switch to a Developer ID), any grant that reads as denied is
    /// reset so macOS stops showing a switch that does nothing, and Accessibility is asked for
    /// again. A `swift run` binary is left alone: its entries are keyed by path, not bundle id.
    static func repairAfterLaunchIfNeeded() {
        guard isBundled else { return }
        let d = UserDefaults.standard
        let previous = d.string(forKey: identityKey)
        d.set(codeIdentity, forKey: identityKey)
        guard previous != codeIdentity else { return }
        NSLog("NotchIsland permissions: identity %@ → %@, checking grants", previous ?? "none", codeIdentity)

        let stale = Permission.allCases.filter { check($0) == .denied }
        for p in stale {
            reset(p) { ok, _ in
                // Accessibility has a dialog; the others wait for the user (Settings ▸ Permissions).
                if ok, p == .accessibility { ask(.accessibility, openPane: false) }
            }
        }
    }
}
