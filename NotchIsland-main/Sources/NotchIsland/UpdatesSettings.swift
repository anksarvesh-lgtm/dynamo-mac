import AppKit
import Combine
import SwiftUI

/// Settings ▸ Updates: this build, the latest release and its notes, Check Now / Update Now, and the
/// daily-check switches.
struct UpdatesSettingsView: View {
    @ObservedObject private var updater = Updater.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var now = Date()
    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("This Mac") {
                HStack(alignment: .top, spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("NotchIsland \(Updater.currentVersion)").font(.headline)
                        Text(statusLine).font(.caption).foregroundStyle(statusTint)
                            .fixedSize(horizontal: false, vertical: true)
                        if let checked = updater.lastChecked {
                            Text("Last checked \(Self.relative(checked, now: now))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    actions.fixedSize()
                }
                .padding(.vertical, 2)
                progress
                if case .failed(let message) = updater.phase {
                    Text(message).font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                if let release = updater.newer, !updater.canInstall {
                    Text(Permissions.isBundled
                         ? "This copy is signed ad hoc, so a download cannot be matched against it. Install \(release.version) from the release page."
                         : "Running from source: builds do not update in place. Install \(release.version) from the release page, or pull and build.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let release = updater.newer {
                Section("What's new in \(release.version)") {
                    notes(release)
                }
            } else if let release = updater.latest {
                Section(Version.compare(release.version, Updater.currentVersion) == .orderedSame
                        ? "What's new in this version" : "Latest release: \(release.version)") {
                    notes(release)
                }
            }

            Section("Automatic") {
                Toggle("Check for updates once a day", isOn: $settings.updatesAutoCheck)
                Toggle("Announce a new version in the island", isOn: $settings.updatesNotify)
                    .disabled(!settings.updatesAutoCheck)
                Text("The check asks GitHub for the latest release of NotchIsland and nothing else: no account, no identifier, nothing about this Mac. It is the only network request the app makes.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("How Update Now works") {
                Text("It downloads the release DMG from GitHub, checks that the app inside is signed with the same certificate as this copy (so every permission you granted carries over), swaps it into place and relaunches. Nothing goes through a browser, so Gatekeeper's \"could not verify\" dialog does not appear. If the folder cannot be written, the DMG opens in Finder for you to drag over by hand.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Releases on GitHub") { updater.openReleasePage() }
            }
        }
        .formStyle(.grouped)
        .onReceive(clock) { now = $0 }
    }

    // MARK: Pieces

    @ViewBuilder private var actions: some View {
        switch updater.phase {
        case .checking:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Checking…").font(.caption) }
        case .downloading, .installing, .relaunching:
            EmptyView()
        case .idle, .failed:
            if let release = updater.newer {
                HStack(spacing: 6) {
                    if updater.canInstall {
                        Button("Update Now") { updater.install() }.buttonStyle(.borderedProminent)
                            .help("Download \(release.version) and install it in place")
                    } else {
                        Button("Download \(release.version)…") { updater.openReleasePage() }.buttonStyle(.borderedProminent)
                    }
                    Button(updater.isSkipped ? "Show Again" : "Skip") { updater.skip(!updater.isSkipped) }
                        .help(updater.isSkipped ? "Announce this version again" : "Stop announcing \(release.version) in the island")
                }
            } else {
                Button("Check Now") { updater.check(manual: true) }
            }
        }
    }

    @ViewBuilder private var progress: some View {
        switch updater.phase {
        case .downloading(let fraction):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: max(0, min(1, fraction)))
                Text("Downloading NotchIsland \(updater.newer?.version ?? "")… \(Self.bytes(fraction, of: updater.newer?.dmgSize ?? 0))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .installing:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Verifying the signature and installing…").font(.caption) }
        case .relaunching:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Installed. Relaunching…").font(.caption)
            }
        default:
            EmptyView()
        }
    }

    private func notes(_ release: AppRelease) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let date = release.publishedAt {
                Text("\(release.title) · \(date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if release.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("No notes for this release.").font(.caption).foregroundStyle(.secondary)
            } else {
                ReleaseNotesView(markdown: release.notes)
            }
            Link("Open the release page", destination: release.pageURL).font(.caption)
        }
        .padding(.vertical, 2)
    }

    private var statusLine: String {
        switch updater.phase {
        case .checking: return "Checking GitHub for a newer version…"
        case .downloading, .installing, .relaunching: return "Updating…"
        case .idle, .failed: break
        }
        if let release = updater.newer {
            return "Version \(release.version) is available" + (updater.isSkipped ? " (skipped)" : "")
        }
        guard let latest = updater.latest else { return "Not checked yet." }
        switch Version.compare(latest.version, Updater.currentVersion) {
        case .orderedSame: return "You're up to date."
        case .orderedAscending: return "This build is newer than the latest release (\(latest.version))."
        case .orderedDescending: return "Version \(latest.version) is available"
        }
    }

    private var statusTint: Color {
        if updater.newer != nil, !updater.phase.isBusy { return .accentColor }
        return .secondary
    }

    static func relative(_ date: Date, now: Date) -> String {
        let s = Int(now.timeIntervalSince(date))
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s / 60) min ago" }
        if s < 86400 { return "\(s / 3600) h ago" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func bytes(_ fraction: Double, of total: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        guard total > 0 else { return String(format: "%.0f%%", fraction * 100) }
        return "\(f.string(fromByteCount: Int64(fraction * Double(total)))) of \(f.string(fromByteCount: total))"
    }
}

/// Enough Markdown for release notes: headings, bullets, numbered lists and paragraphs, with
/// inline bold / code / links. GitHub's notes are what the Changelog carries.
struct ReleaseNotesView: View {
    let markdown: String

    enum Block: Equatable {
        case heading(String)
        case bullet(String)
        case numbered(String, String)
        case paragraph(String)
    }

    var body: some View {
        let blocks = Self.parse(markdown)
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                switch block {
                case .heading(let text):
                    Text(text).font(.subheadline.weight(.semibold))
                        .padding(.top, index == 0 ? 0 : 6)
                case .bullet(let text):
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").font(.system(size: 12)).foregroundStyle(.secondary)
                        inline(text)
                    }
                case .numbered(let n, let text):
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(n).").font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                        inline(text)
                    }
                case .paragraph(let text):
                    inline(text)
                }
            }
        }
        .textSelection(.enabled)
    }

    private func inline(_ text: String) -> some View {
        let rendered: Text
        if let a = try? AttributedString(markdown: text,
                                         options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            rendered = Text(a)
        } else {
            rendered = Text(text)
        }
        return rendered.font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
    }

    static func parse(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        for raw in markdown.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#") {
                let title = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                if title.caseInsensitiveCompare("Install") == .orderedSame { break }   // DMG steps; Update Now covers it
                blocks.append(.heading(title))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                blocks.append(.bullet(String(line.dropFirst(2))))
            } else if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty,
                      line[line.index(after: dot)...].hasPrefix(" ") {
                blocks.append(.numbered(String(line[..<dot]), line[line.index(after: dot)...].trimmingCharacters(in: .whitespaces)))
            } else {
                // Continuation of the previous bullet / paragraph (wrapped source lines).
                switch blocks.last {
                case .bullet(let t): blocks[blocks.count - 1] = .bullet(t + " " + line)
                case .numbered(let n, let t): blocks[blocks.count - 1] = .numbered(n, t + " " + line)
                case .paragraph(let t): blocks[blocks.count - 1] = .paragraph(t + " " + line)
                default: blocks.append(.paragraph(line))
                }
            }
        }
        return blocks
    }
}
