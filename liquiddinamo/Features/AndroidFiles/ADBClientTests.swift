//
//  ADBClientTests.swift
//  LiquidDynamo
//
//  Unit tests for ADBClient: shell escaping, ls/stat parser, connection states,
//  path normalization, and scoped storage restriction verification.
//

import Foundation

public final class ADBClientTests {
    public static func runAllTests() -> Bool {
        print("🧪 [ADBClientTests] Starting unit tests...")
        var passed = 0
        var failed = 0

        func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
            if actual == expected {
                passed += 1
            } else {
                print("❌ FAILED: \(message) — Expected '\(expected)', got '\(actual)'")
                failed += 1
            }
        }

        func assertTrue(_ condition: Bool, _ message: String) {
            if condition {
                passed += 1
            } else {
                print("❌ FAILED: \(message)")
                failed += 1
            }
        }

        // 1. Shell Escaping Tests
        print("  1. Testing Shell Escaping...")
        assertEqual(ADBShellSecurity.escape("simple"), "'simple'", "Simple string escape")
        assertEqual(ADBShellSecurity.escape("with space"), "'with space'", "Space string escape")
        assertEqual(ADBShellSecurity.escape("O'Reilly"), "'O'\\''Reilly'", "Single quote escape")
        assertEqual(ADBShellSecurity.escape("foo; rm -rf /"), "'foo; rm -rf /'", "Command injection semicolon escape")
        assertEqual(ADBShellSecurity.escape("$VAR `calc`"), "'$VAR `calc`'", "Variable and backtick escape")
        assertEqual(ADBShellSecurity.escape("emoji_🎉_folder"), "'emoji_🎉_folder'", "Unicode emoji escape")
        assertEqual(ADBShellSecurity.escape("-leading-dash"), "'-leading-dash'", "Leading dash escape")
        assertEqual(ADBShellSecurity.escape("line1\nline2"), "'line1\nline2'", "Newline in filename escape")

        // 2. Path Normalization Tests
        print("  2. Testing Path Normalization...")
        assertEqual(ADBShellSecurity.normalizeRemotePath("sdcard/DCIM"), "/sdcard/DCIM", "Missing leading slash")
        assertEqual(ADBShellSecurity.normalizeRemotePath("/sdcard/DCIM/"), "/sdcard/DCIM", "Trailing slash removal")
        assertEqual(ADBShellSecurity.normalizeRemotePath("///storage///emulated//0/"), "/storage/emulated/0", "Duplicate slash collapse")
        assertEqual(ADBShellSecurity.normalizeRemotePath(""), "/", "Empty path to root")

        // 3. Android 11+ Scoped Storage Restriction Detection
        print("  3. Testing Scoped Storage Restrictions...")
        assertTrue(ADBShellSecurity.isScopedStorageRestricted(path: "/sdcard/Android/data"), "/sdcard/Android/data restriction")
        assertTrue(ADBShellSecurity.isScopedStorageRestricted(path: "/storage/emulated/0/Android/obb"), "/storage/emulated/0/Android/obb restriction")
        assertTrue(ADBShellSecurity.isScopedStorageRestricted(path: "/Android/data/com.app"), "Subfolder under Android/data restriction")
        assertTrue(!ADBShellSecurity.isScopedStorageRestricted(path: "/sdcard/DCIM/Camera"), "/sdcard/DCIM/Camera should not be restricted")
        assertTrue(!ADBShellSecurity.isScopedStorageRestricted(path: "/sdcard/Download"), "/sdcard/Download should not be restricted")

        // 4. Toybox `ls -lA` Output Parsing Tests
        print("  4. Testing Directory Listing Parser...")
        let sampleOutput = """
        total 16
        drwxrwx--x  4 root sdcard_rw     4096 2026-10-24 12:30 DCIM
        drwxrwx--x  3 root sdcard_rw     4096 2026-10-24 12:30 Pictures
        -rw-rw----  1 root sdcard_rw 12345678 2026-10-24 14:15 Vacation Photo.jpg
        -rw-rw----  1 root sdcard_rw   102400 2026-10-24 14:16 Notes & Quotes.txt
        lrwxrwxrwx  1 root root            21 2026-10-24 10:00 sdcard -> /storage/emulated/0
        -rw-rw----  1 root sdcard_rw      512 2026-10-24 11:00 .hidden_config
        """

        let parsedHidden = ADBDirectoryParser.parseListing(sampleOutput, parentPath: "/sdcard", showHidden: true)
        assertEqual(parsedHidden.count, 6, "Total entries parsed including hidden")

        let parsedNoHidden = ADBDirectoryParser.parseListing(sampleOutput, parentPath: "/sdcard", showHidden: false)
        assertEqual(parsedNoHidden.count, 5, "Total entries parsed excluding hidden")

        if let dcim = parsedNoHidden.first(where: { $0.name == "DCIM" }) {
            assertTrue(dcim.isDirectory, "DCIM is directory")
            assertEqual(dcim.path, "/sdcard/DCIM", "DCIM path")
        } else {
            print("❌ FAILED: DCIM entry not found")
            failed += 1
        }

        if let photo = parsedNoHidden.first(where: { $0.name == "Vacation Photo.jpg" }) {
            assertTrue(!photo.isDirectory, "Photo is not directory")
            assertTrue(photo.isImage, "Photo classified as image")
            assertEqual(photo.size, 12345678, "Photo byte size")
            assertEqual(photo.path, "/sdcard/Vacation Photo.jpg", "Photo space path")
        } else {
            print("❌ FAILED: Vacation Photo.jpg entry not found")
            failed += 1
        }

        if let symlink = parsedNoHidden.first(where: { $0.name == "sdcard" }) {
            assertTrue(symlink.isSymlink, "sdcard is symlink")
            assertEqual(symlink.symlinkTarget, "/storage/emulated/0", "sdcard symlink target")
        } else {
            print("❌ FAILED: sdcard symlink entry not found")
            failed += 1
        }

        // 5. Connection State Text Mapping Tests
        print("  5. Testing Connection State Mapping...")
        let s1 = ADBConnectionState.noAdb
        assertEqual(s1.displayText, "ADB not found", "No ADB text")
        let s2 = ADBConnectionState.unauthorized(serial: "123")
        assertTrue(s2.displayText.contains("Unauthorized"), "Unauthorized text contains prompt")
        let dev = ADBDeviceInfo(serial: "MOTO123", model: "motorola edge 50")
        let s3 = ADBConnectionState.ready(device: dev)
        assertTrue(s3.isReady, "Ready state isReady")
        assertEqual(s3.displayText, "motorola edge 50", "Ready state device name")

        print("🏁 [ADBClientTests] Finished: \(passed) passed, \(failed) failed.")
        return failed == 0
    }
}
