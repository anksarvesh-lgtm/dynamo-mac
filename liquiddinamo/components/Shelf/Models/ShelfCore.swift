//
//  ShelfCore.swift
//  LiquidDynamo
//
//  Pure Foundation shelf collection transforms, filename sanitization,
//  and Sandbox-honest permission status policy helpers.
//

import Foundation

/// Minimal metadata interface required by ``ShelfPolicy`` list transforms.
public protocol ShelfTrackable {
    var identityKey: String { get }
    var isTemporary: Bool { get }
    var createdAt: Date { get }
}

/// Lightweight value model for unit-testing ``ShelfPolicy`` without AppKit/UI coupling.
public struct ShelfEntryMetadata: ShelfTrackable, Equatable, Sendable {
    public let id: UUID
    public let identityKey: String
    public let isTemporary: Bool
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        identityKey: String,
        isTemporary: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.identityKey = identityKey
        self.isTemporary = isTemporary
        self.createdAt = createdAt
    }
}

/// Pure, bounded collection and filename policies for the File Shelf.
public enum ShelfPolicy {
    public static let defaultMaxItems: Int = 24
    public static let defaultTemporaryTTL: TimeInterval = 3600

    /// Inserts `item` at the front (newest first), deduplicates any existing entry with
    /// the same `identityKey`, enforces `maxItems` (when `> 0`), and returns any evicted items
    /// so the caller can reclaim temporary files or security-scoped bookmarks.
    public static func inserting<Item: ShelfTrackable>(
        _ item: Item,
        into items: [Item],
        maxItems: Int = defaultMaxItems
    ) -> (items: [Item], evicted: [Item]) {
        var result = [item] + items.filter { $0.identityKey != item.identityKey }
        guard maxItems > 0, result.count > maxItems else {
            return (result, [])
        }
        let evicted = Array(result[maxItems...])
        result = Array(result[..<maxItems])
        return (result, evicted)
    }

    /// Inserts a batch of items at the front while preserving batch order, deduplicating
    /// by `identityKey`, and returning any capacity-evicted trailing items.
    public static func inserting<Item: ShelfTrackable>(
        contentsOf newItems: [Item],
        into items: [Item],
        maxItems: Int = defaultMaxItems
    ) -> (items: [Item], evicted: [Item]) {
        guard !newItems.isEmpty else {
            guard maxItems > 0, items.count > maxItems else { return (items, []) }
            return (Array(items[..<maxItems]), Array(items[maxItems...]))
        }

        var uniqueBatch: [Item] = []
        var seenKeys = Set<String>()
        for candidate in newItems {
            if !seenKeys.contains(candidate.identityKey) {
                seenKeys.insert(candidate.identityKey)
                uniqueBatch.append(candidate)
            }
        }

        var result = uniqueBatch + items.filter { !seenKeys.contains($0.identityKey) }
        guard maxItems > 0, result.count > maxItems else {
            return (result, [])
        }
        let evicted = Array(result[maxItems...])
        result = Array(result[..<maxItems])
        return (result, evicted)
    }

    /// Moves the item matching `identityKey` to index `0`. No-op if absent.
    public static func moveToFront<Item: ShelfTrackable>(
        identityKey: String,
        in items: [Item]
    ) -> [Item] {
        guard let item = items.first(where: { $0.identityKey == identityKey }) else {
            return items
        }
        return [item] + items.filter { $0.identityKey != identityKey }
    }

    /// Removes any items matching `identityKey`.
    public static func removing<Item: ShelfTrackable>(
        identityKey: String,
        from items: [Item]
    ) -> [Item] {
        items.filter { $0.identityKey != identityKey }
    }

    /// Returns temporary items whose age equals or exceeds `ttl`.
    public static func expiredItems<Item: ShelfTrackable>(
        in items: [Item],
        now: Date = Date(),
        ttl: TimeInterval = defaultTemporaryTTL
    ) -> [Item] {
        items.filter { $0.isTemporary && now.timeIntervalSince($0.createdAt) >= ttl }
    }

    /// Sanitizes an untrusted filename so it stays single-component, non-hidden,
    /// free of control/path characters, and bounded in length while preserving its extension.
    public static func sanitizeFilename(
        _ rawName: String?,
        fallback: String = "item.dat",
        maxLength: Int = 180
    ) -> String {
        let safeFallback = fallback.isEmpty ? "item.dat" : fallback
        guard let rawName else { return safeFallback }

        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return safeFallback }

        let forbiddenChars = CharacterSet(charactersIn: "/\\:\0")
            .union(.controlCharacters)
            .union(.newlines)
        var cleanedScalars = String.UnicodeScalarView()
        for scalar in trimmed.unicodeScalars {
            if forbiddenChars.contains(scalar) {
                cleanedScalars.append("-")
            } else {
                cleanedScalars.append(scalar)
            }
        }

        var candidate = String(cleanedScalars)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Prevent hidden dotfiles or directory traversal segments (".", "..").
        while candidate.hasPrefix(".") {
            candidate.removeFirst()
        }
        candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !candidate.isEmpty,
              !candidate.allSatisfy({ $0 == "." || $0 == "-" }) else {
            return safeFallback
        }

        let effectiveMax = max(16, maxLength)
        guard candidate.count > effectiveMax else {
            return candidate
        }

        let url = URL(fileURLWithPath: candidate)
        let ext = url.pathExtension
        if !ext.isEmpty, ext.count + 2 < effectiveMax {
            let suffix = ".\(ext)"
            let stemBudget = effectiveMax - suffix.count
            let stem = String(candidate.prefix(stemBudget))
            return stem + suffix
        }
        return String(candidate.prefix(effectiveMax))
    }

    /// Computes a deterministic archive filename for single or multi-item shelf compression.
    public static func archiveFilename(itemCount: Int, primaryName: String?) -> String {
        if itemCount <= 1 {
            let base = sanitizeFilename(primaryName, fallback: "Archive")
            let stripped = URL(fileURLWithPath: base).deletingPathExtension().lastPathComponent
            let cleanBase = sanitizeFilename(stripped, fallback: "Archive", maxLength: 140)
            return "\(cleanBase).zip"
        }
        return "LiquidDynamo-Archive-\(itemCount)-items.zip"
    }
}

/// Pure Foundation decision states mapped onto UI permission badges in ``AppPermissionManager``.
public enum PermissionCompanionDecision: String, Sendable, Equatable {
    case allowed
    case needsPermission
    case needsRepair
    case notNeeded
    case unverifiedTargetNotRunning
}

/// Pure policy decisions for lazy, Sandbox-honest permission checks and repairs.
public enum PermissionCompanionPolicy {
    /// Determines Full Disk Access badge state without over-reporting container-local reads.
    public static func fullDiskAccessDecision(
        isSandboxed: Bool,
        probeGranted: Bool
    ) -> PermissionCompanionDecision {
        if probeGranted {
            return .allowed
        }
        return isSandboxed ? .notNeeded : .needsPermission
    }

    /// Maps `AEDeterminePermissionToAutomateTarget` OSStatus codes conservatively.
    /// `-600` (`procNotFound`) indicates the target app is not running and cannot be assumed `.allowed`.
    public static func automationDecision(osStatus: Int32) -> PermissionCompanionDecision {
        switch osStatus {
        case 0: // noErr
            return .allowed
        case -600: // procNotFound
            return .unverifiedTargetNotRunning
        case -1743, // errAEEventNotPermitted
             -1744, // errAEEventWouldRequireUserConsent
             -10004: // errAEPrivilegeError
            return .needsPermission
        default:
            return .needsPermission
        }
    }

    /// Resolves Accessibility state without claiming repair is needed unless a session grant lapsed.
    public static func accessibilityDecision(
        isTrusted: Bool,
        hadPriorGrantInSession: Bool
    ) -> PermissionCompanionDecision {
        if isTrusted {
            return .allowed
        }
        return hadPriorGrantInSession ? .needsRepair : .needsPermission
    }

    /// `tccutil` subprocesses are disallowed inside App Sandbox and must only run in non-sandboxed builds.
    public static func shouldSpawnTCCReset(isSandboxed: Bool) -> Bool {
        !isSandboxed
    }
}
