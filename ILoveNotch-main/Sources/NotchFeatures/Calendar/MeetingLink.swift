// SPDX-License-Identifier: MIT
import Foundation

/// A video call's link in a calendar event: Zoom, Google Meet, Microsoft Teams, Webex, Whereby,
/// Jitsi Meet, or FaceTime.
public struct MeetingLink: Hashable, Sendable {
    public var url: URL
    /// The service's name, for the Join button's help.
    public var service: String

    /// The first meeting link in `texts`, looked for in order: an event's URL, its location, then
    /// its notes, since some invites carry the link only in the notes.
    public static func find(in texts: [String?]) -> MeetingLink? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        for text in texts.compactMap({ $0 }) where !text.isEmpty {
            for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let url = match.url, let link = MeetingLink(url) { return link }
            }
        }
        return nil
    }

    /// `url` if it joins a meeting on one of the services, or nil for any other link, including the
    /// services' own home and help pages.
    init?(_ url: URL) {
        guard url.scheme == "https" || url.scheme == "http", let host = url.host()?.lowercased(),
            let service = Self.service(host: host, path: url.path().lowercased())
        else { return nil }
        self.url = url
        self.service = service
    }

    private static func service(host: String, path: String) -> String? {
        func on(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
        if on("zoom.us") || on("zoomgov.com") {
            return ["/j/", "/my/", "/w/", "/s/"].contains { path.hasPrefix($0) } ? "Zoom" : nil
        }
        if host == "meet.google.com" {
            let code = path.range(of: "^/[a-z]{3}-[a-z]{4}-[a-z]{3}($|/)", options: .regularExpression)
            return code != nil || path.hasPrefix("/lookup/") ? "Google Meet" : nil
        }
        if host == "teams.microsoft.com" || host == "teams.live.com" {
            return path.contains("/meetup-join/") || path.hasPrefix("/meet/") ? "Microsoft Teams" : nil
        }
        if on("webex.com") {
            return ["/meet/", "/j.php", "/join/", "/wbxmjs/"].contains { path.contains($0) } ? "Webex" : nil
        }
        if on("whereby.com") { return path.count > 1 ? "Whereby" : nil }
        if host == "meet.jit.si" { return path.count > 1 ? "Jitsi Meet" : nil }
        if host == "facetime.apple.com" { return path.hasPrefix("/join") ? "FaceTime" : nil }
        return nil
    }
}
