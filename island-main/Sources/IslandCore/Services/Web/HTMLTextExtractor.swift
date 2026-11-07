import Foundation

/// Dependency-free readable-text extraction from HTML for research summarisation.
public enum HTMLTextExtractor {
    public static func title(_ html: String) -> String? {
        guard let r = html.range(of: "<title[^>]*>([\\s\\S]*?)</title>", options: [.regularExpression, .caseInsensitive]) else { return nil }
        let inner = html[r].replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let t = decodeEntities(inner).trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    public static func text(_ html: String, limit: Int = 6000) -> String {
        var s = html
        for tag in ["script", "style", "noscript", "svg", "nav", "footer", "header", "aside", "form", "iframe"] {
            s = s.replacingOccurrences(of: "<\(tag)\\b[\\s\\S]*?</\(tag)>", with: " ", options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "<(br|p|div|li|h[1-6]|tr)\\b[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = decodeEntities(s)
        s = s.replacingOccurrences(of: "[ \\t\\u{00A0}]+", with: " ", options: .regularExpression)
        let lines = s.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.count > 30 }
        let joined = lines.joined(separator: "\n")
        return joined.count > limit ? String(joined.prefix(limit)) : joined
    }

    public static func decodeEntities(_ s: String) -> String {
        var out = s
        let map = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " ", "&#x27;": "'", "&mdash;": "—", "&ndash;": "–", "&hellip;": "…"]
        for (k, v) in map { out = out.replacingOccurrences(of: k, with: v) }
        // Numeric entities.
        while let r = out.range(of: "&#(x?[0-9a-fA-F]+);", options: .regularExpression) {
            let body = out[r].dropFirst(2).dropLast()
            let scalar = body.hasPrefix("x") ? UInt32(body.dropFirst(), radix: 16) : UInt32(body)
            out.replaceSubrange(r, with: scalar.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? "")
        }
        return out
    }

    /// Strips tags from short snippets (search APIs often return `<span class="searchmatch">`).
    public static func plain(_ s: String) -> String {
        decodeEntities(s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
