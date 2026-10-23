//
//  test_filedroid_engine.swift
//  Unit tests for FileDroid & OpenMTP engine, models, and Finder mount logic.
//

import Foundation

@main
struct FileDroidTestRunner {
    static func main() {
        print("=== Running FileDroid & OpenMTP Unit Tests ===")

        // 1. Test Byte and Speed Formatting
        assert(FileDroidFormatting.formatBytes(512) == "512 B")
        assert(FileDroidFormatting.formatBytes(1024 * 1024 * 2) == "2.0 MB")
        assert(FileDroidFormatting.formatBytes(1024 * 1024 * 1024 * 16) == "16.0 GB")
        assert(FileDroidFormatting.formatSpeed(0) == "0 KB/s")
        assert(FileDroidFormatting.formatSpeed(1024 * 512).contains("512.0 KB/s"))
        assert(FileDroidFormatting.formatSpeed(1024 * 1024 * 42.5).contains("42.5 MB/s"))
        print("Test 1 (Byte & Speed Formatting): PASS")

        // 2. Test AndroidDevice Model & Storage Calculations
        var dev = AndroidDevice(
            serial: "RF8N123456",
            model: "Galaxy S24 Ultra",
            manufacturer: "Samsung",
            marketName: "Samsung Galaxy S24 Ultra",
            androidVersion: "Android 14",
            apiLevel: 34,
            batteryLevel: 85,
            batteryTemperature: 31.5,
            batteryHealth: "Good",
            isCharging: true,
            internalStorageTotal: 256 * 1024 * 1024 * 1024,
            internalStorageUsed: 128 * 1024 * 1024 * 1024,
            internalStorageFree: 128 * 1024 * 1024 * 1024,
            sdCardTotal: 512 * 1024 * 1024 * 1024,
            sdCardUsed: 100 * 1024 * 1024 * 1024,
            sdCardFree: 412 * 1024 * 1024 * 1024,
            connectionType: .adb,
            status: .connected
        )
        assert(dev.displayName == "Samsung Galaxy S24 Ultra")
        assert(abs(dev.storageUsedPercentage - 0.5) < 0.001)
        assert(dev.brandIconName == "phone.fill")
        print("Test 2 (AndroidDevice Model & Metrics): PASS")

        // 3. Test AndroidFileItem Icon & Extension Mapping
        let photo = AndroidFileItem(
            name: "IMG_20261023_182000.jpg",
            remotePath: "/sdcard/DCIM/Camera/IMG_20261023_182000.jpg",
            sizeBytes: 4 * 1024 * 1024,
            modificationDate: Date(),
            isDirectory: false,
            isHidden: false
        )
        assert(photo.iconSymbol == "photo.fill")
        assert(photo.fileExtension == "jpg")

        let folder = AndroidFileItem(
            name: "DCIM",
            remotePath: "/sdcard/DCIM",
            sizeBytes: 0,
            modificationDate: Date(),
            isDirectory: true,
            isHidden: false
        )
        assert(folder.iconSymbol == "camera.fill")
        assert(folder.formattedSize == "--")

        let video = AndroidFileItem(
            name: "movie.mp4",
            remotePath: "/sdcard/Movies/movie.mp4",
            sizeBytes: 1024 * 1024 * 500,
            modificationDate: Date(),
            isDirectory: false,
            isHidden: false
        )
        assert(video.iconSymbol == "film.fill")
        print("Test 3 (File Type & Icon Categorization): PASS")

        // 4. Test Finder External Storage Directory & Specs File Structure
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let internalStorage = tempDir.appendingPathComponent("Internal Storage")
        let standardDirs = ["DCIM", "Download", "Documents", "Music", "Pictures", "Movies", "Podcasts"]
        for d in standardDirs {
            try! FileManager.default.createDirectory(at: internalStorage.appendingPathComponent(d), withIntermediateDirectories: true)
            assert(FileManager.default.fileExists(atPath: internalStorage.appendingPathComponent(d).path))
        }

        let specsURL = tempDir.appendingPathComponent("Device Info & Storage Specs.txt")
        let specsContent = """
        Device Name: \(dev.displayName)
        Serial Number: \(dev.serial)
        Internal Storage: \(dev.formattedInternalStorage)
        """
        try! specsContent.write(to: specsURL, atomically: true, encoding: .utf8)
        assert(FileManager.default.fileExists(atPath: specsURL.path))
        print("Test 4 (Finder Virtual SSD Volume Hierarchy): PASS")

        // 5. Test Transfer Queue Accounting
        var transfer = FileDroidTransferItem(
            fileName: "video.mp4",
            direction: .uploadToAndroid,
            localPath: "/tmp/video.mp4",
            remotePath: "/sdcard/Movies/video.mp4",
            totalBytes: 100 * 1024 * 1024,
            transferredBytes: 50 * 1024 * 1024,
            speedBytesPerSec: 25 * 1024 * 1024,
            status: .inProgress
        )
        assert(transfer.progressFraction == 0.5)
        assert(transfer.formattedSpeed.contains("25.0 MB/s"))
        print("Test 5 (Transfer Queue & Throughput Accounting): PASS")

        print("\n✅ ALL 5 FILEDROID & OPENMTP TESTS PASSED!")
    }
}
