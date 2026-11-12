import Foundation

struct ShelfPermissionTestsRunner {
    private var failures = 0

    mutating func expect(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
        if !condition {
            fputs("FAIL [\(file):\(line)]: \(message)\n", stderr)
            failures += 1
        }
    }

    mutating func run() {
        testSingleInsertionDeduplicationAndCap()
        testBatchInsertionOrderAndEviction()
        testMoveToFrontAndRemoval()
        testTemporaryExpiryBoundary()
        testFilenameSanitizationAndArchiveNaming()
        testPermissionCompanionPolicySandboxHonesty()

        if failures == 0 {
            print("ShelfPermissionTests: ALL PASSED")
        } else {
            fputs("ShelfPermissionTests: \(failures) FAILURE(S)\n", stderr)
            exit(1)
        }
    }

    mutating func testSingleInsertionDeduplicationAndCap() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let a = ShelfEntryMetadata(identityKey: "file:/a.png", isTemporary: false, createdAt: now)
        let b = ShelfEntryMetadata(identityKey: "file:/b.png", isTemporary: true, createdAt: now)
        let c = ShelfEntryMetadata(identityKey: "file:/c.png", isTemporary: false, createdAt: now)
        let aReadded = ShelfEntryMetadata(identityKey: "file:/a.png", isTemporary: false, createdAt: now.addingTimeInterval(5))

        var list: [ShelfEntryMetadata] = []
        var evicted: [ShelfEntryMetadata] = []

        (list, evicted) = ShelfPolicy.inserting(a, into: list, maxItems: 2)
        expect(list.map(\.identityKey) == ["file:/a.png"] && evicted.isEmpty, "First insert keeps 1 item")

        (list, evicted) = ShelfPolicy.inserting(b, into: list, maxItems: 2)
        expect(list.map(\.identityKey) == ["file:/b.png", "file:/a.png"] && evicted.isEmpty, "Newest item prepends to index 0")

        // Re-adding `a` moves it to front with zero eviction because count stays 2.
        (list, evicted) = ShelfPolicy.inserting(aReadded, into: list, maxItems: 2)
        expect(list.map(\.identityKey) == ["file:/a.png", "file:/b.png"], "Re-adding existing identityKey promotes to front")
        expect(list.first?.createdAt == aReadded.createdAt && evicted.isEmpty, "Re-add replaces metadata without eviction")

        // Adding `c` exceeds maxItems = 2 and evicts `b` at the tail.
        (list, evicted) = ShelfPolicy.inserting(c, into: list, maxItems: 2)
        expect(list.map(\.identityKey) == ["file:/c.png", "file:/a.png"], "Cap keeps newest 2 items")
        expect(evicted.map(\.identityKey) == ["file:/b.png"], "Tail item b is evicted")

        // Zero cap means unbounded.
        let (unbounded, noneEvicted) = ShelfPolicy.inserting(b, into: list, maxItems: 0)
        expect(unbounded.count == 3 && noneEvicted.isEmpty, "maxItems <= 0 allows unbounded growth")
    }

    mutating func testBatchInsertionOrderAndEviction() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let existing = [
            ShelfEntryMetadata(identityKey: "file:/1.txt", isTemporary: true, createdAt: now),
            ShelfEntryMetadata(identityKey: "file:/2.txt", isTemporary: false, createdAt: now),
            ShelfEntryMetadata(identityKey: "file:/3.txt", isTemporary: true, createdAt: now),
        ]
        let dropped = [
            ShelfEntryMetadata(identityKey: "file:/4.txt", isTemporary: false, createdAt: now),
            ShelfEntryMetadata(identityKey: "file:/2.txt", isTemporary: false, createdAt: now.addingTimeInterval(1)),
            ShelfEntryMetadata(identityKey: "file:/4.txt", isTemporary: false, createdAt: now.addingTimeInterval(9)),
        ]

        let (merged, evicted) = ShelfPolicy.inserting(contentsOf: dropped, into: existing, maxItems: 3)
        expect(merged.map(\.identityKey) == ["file:/4.txt", "file:/2.txt", "file:/1.txt"], "Batch preserves drop order, promotes duplicates, and caps at 3")
        expect(evicted.map(\.identityKey) == ["file:/3.txt"], "Oldest non-readded item should be evicted")
    }

    mutating func testMoveToFrontAndRemoval() {
        let now = Date(timeIntervalSince1970: 3_000_000)
        let list = [
            ShelfEntryMetadata(identityKey: "k1", createdAt: now),
            ShelfEntryMetadata(identityKey: "k2", createdAt: now),
            ShelfEntryMetadata(identityKey: "k3", createdAt: now),
        ]

        let moved = ShelfPolicy.moveToFront(identityKey: "k3", in: list)
        expect(moved.map(\.identityKey) == ["k3", "k1", "k2"], "moveToFront should promote matching entry")
        expect(ShelfPolicy.moveToFront(identityKey: "missing", in: list) == list, "moveToFront on missing key is a no-op")
        expect(ShelfPolicy.removing(identityKey: "k2", from: list).map(\.identityKey) == ["k1", "k3"], "removing filters matching key")
    }

    mutating func testTemporaryExpiryBoundary() {
        let base = Date(timeIntervalSince1970: 4_000_000)
        let tempOld = ShelfEntryMetadata(identityKey: "t1", isTemporary: true, createdAt: base.addingTimeInterval(-3600))
        let tempFresh = ShelfEntryMetadata(identityKey: "t2", isTemporary: true, createdAt: base.addingTimeInterval(-3599))
        let persistentOld = ShelfEntryMetadata(identityKey: "p1", isTemporary: false, createdAt: base.addingTimeInterval(-86_400))

        let expired = ShelfPolicy.expiredItems(in: [tempOld, tempFresh, persistentOld], now: base, ttl: 3600)
        expect(expired.map(\.identityKey) == ["t1"], "Only temporary items at or past TTL should expire")
    }

    mutating func testFilenameSanitizationAndArchiveNaming() {
        expect(ShelfPolicy.sanitizeFilename(nil) == "item.dat", "nil name uses fallback")
        expect(ShelfPolicy.sanitizeFilename("   \n ") == "item.dat", "whitespace-only uses fallback")
        expect(ShelfPolicy.sanitizeFilename(".") == "item.dat", "single dot rejected")
        expect(ShelfPolicy.sanitizeFilename("..") == "item.dat", "parent traversal rejected")
        expect(ShelfPolicy.sanitizeFilename(".dat") == "dat", "leading dot stripped so visible file remains valid")
        expect(ShelfPolicy.sanitizeFilename("...") == "item.dat", "all-dot name falls back")

        let escaped = ShelfPolicy.sanitizeFilename("../../etc/passwd:raw\0\n")
        expect(!escaped.contains("/") && !escaped.contains("\\") && !escaped.contains(":") && !escaped.hasPrefix("."), "Path separators, colons, nulls, and leading dots must be neutralized: got \(escaped)")

        let longName = String(repeating: "a", count: 220) + ".png"
        let clamped = ShelfPolicy.sanitizeFilename(longName, maxLength: 64)
        expect(clamped.count == 64 && clamped.hasSuffix(".png"), "Long filename clamps to maxLength while preserving extension")

        expect(ShelfPolicy.archiveFilename(itemCount: 1, primaryName: "Report 2026.pdf") == "Report 2026.zip", "Single archive strips source extension and appends .zip")
        expect(ShelfPolicy.archiveFilename(itemCount: 4, primaryName: "A.png") == "LiquidDynamo-Archive-4-items.zip", "Multi archive names count clearly")
    }

    mutating func testPermissionCompanionPolicySandboxHonesty() {
        expect(
            PermissionCompanionPolicy.fullDiskAccessDecision(isSandboxed: true, probeGranted: false) == .notNeeded,
            "Ungranted FDA inside App Sandbox reports .notNeeded instead of misleading warning"
        )
        expect(
            PermissionCompanionPolicy.fullDiskAccessDecision(isSandboxed: false, probeGranted: false) == .needsPermission,
            "Non-sandboxed missing FDA reports .needsPermission"
        )
        expect(
            PermissionCompanionPolicy.fullDiskAccessDecision(isSandboxed: true, probeGranted: true) == .allowed,
            "Genuine probe grant returns .allowed even if sandboxed"
        )

        expect(PermissionCompanionPolicy.automationDecision(osStatus: 0) == .allowed, "noErr maps to allowed")
        expect(PermissionCompanionPolicy.automationDecision(osStatus: -600) == .unverifiedTargetNotRunning, "procNotFound maps to unverifiedTargetNotRunning instead of false allowed")
        expect(PermissionCompanionPolicy.automationDecision(osStatus: -1743) == .needsPermission, "errAEEventNotPermitted maps to needsPermission")
        expect(PermissionCompanionPolicy.automationDecision(osStatus: -1744) == .needsPermission, "errAEEventWouldRequireUserConsent maps to needsPermission")
        expect(PermissionCompanionPolicy.automationDecision(osStatus: -10004) == .needsPermission, "errAEPrivilegeError maps to needsPermission")

        expect(PermissionCompanionPolicy.accessibilityDecision(isTrusted: true, hadPriorGrantInSession: false) == .allowed, "Trusted returns allowed")
        expect(PermissionCompanionPolicy.accessibilityDecision(isTrusted: false, hadPriorGrantInSession: false) == .needsPermission, "Untrusted fresh session returns needsPermission")
        expect(PermissionCompanionPolicy.accessibilityDecision(isTrusted: false, hadPriorGrantInSession: true) == .needsRepair, "Lost trust after prior grant returns needsRepair")

        expect(PermissionCompanionPolicy.shouldSpawnTCCReset(isSandboxed: true) == false, "Must never spawn tccutil inside App Sandbox")
        expect(PermissionCompanionPolicy.shouldSpawnTCCReset(isSandboxed: false) == true, "Non-sandboxed builds may use tccutil repair")
    }
}

var runner = ShelfPermissionTestsRunner()
runner.run()
