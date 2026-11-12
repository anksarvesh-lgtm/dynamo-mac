//
//  TemporaryFileStorageService.swift
//  LiquidDynamo
//
//  LiquidDynamo Core Team
//

import Foundation
import AppKit
import UniformTypeIdentifiers

enum TempFileType {
    case data(Data, suggestedName: String?)
    case text(String)
    case url(URL)
}

class TemporaryFileStorageService {
    static let shared = TemporaryFileStorageService()
    
    // MARK: - Public Interface
    
    /// Creates a temporary file and tracks it for manual cleanup
    func createTempFile(for type: TempFileType) async -> URL? {
        return await withCheckedContinuation { continuation in
            let result = createTempFile(for: type)
            continuation.resume(returning: result)
        }
    }
    
    func removeTemporaryFileIfNeeded(at url: URL) {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())

        guard url.path.hasPrefix(tempDirectory.path) else {
            print("Attempted to remove temporary file outside temp directory: \(url.path)")
            return
        }

        let folderURL = url.deletingLastPathComponent()

        do {
            try FileManager.default.removeItem(at: url)
            print("Deleted file: \(url.path)")

            let contents = try FileManager.default.contentsOfDirectory(atPath: folderURL.path)
            if contents.isEmpty {
                try FileManager.default.removeItem(at: folderURL)
                print("Folder was empty, deleted folder: \(folderURL.path)")
            } else {
                print("Folder not deleted — it still contains \(contents.count) item(s).")
            }

        } catch {
            print("Error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Implementation
    
    private func createTempFile(for type: TempFileType) -> URL? {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let uuid = UUID().uuidString
        
        switch type {
        case .data(let data, let suggestedName):
            let filename = ShelfPolicy.sanitizeFilename(suggestedName, fallback: "item.dat")
            let dirURL = tempDir.appendingPathComponent(uuid, isDirectory: true)
            let fileURL = dirURL.appendingPathComponent(filename)
            
            do {
                try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                try data.write(to: fileURL)
                return fileURL
            } catch {
                print("Error: \(error)")
                return nil
            }
            
        case .text(let string):
            let filename = "\(uuid).txt"
            let dirURL = tempDir.appendingPathComponent(uuid, isDirectory: true)
            let fileURL = dirURL.appendingPathComponent(filename)
            
            guard let data = string.data(using: .utf8) else {
                print("❌ Failed to convert text to data")
                return nil
            }
            
            do {
                try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                try data.write(to: fileURL)
                return fileURL
            } catch {
                print("Error: \(error)")
                return nil
            }
            
        case .url(let url):
            let safeHost = ShelfPolicy.sanitizeFilename(url.host, fallback: uuid)
            let filename = "\(safeHost).webloc"
            let dirURL = tempDir.appendingPathComponent(uuid, isDirectory: true)
            let fileURL = dirURL.appendingPathComponent(filename)
            
            let weblocContent = createWeblocContent(for: url)
            guard let data = weblocContent.data(using: String.Encoding.utf8) else {
                print("❌ Failed to create webloc data")
                return nil
            }
            
            do {
                try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                try data.write(to: fileURL)
                return fileURL
            } catch {
                print("Error: \(error)")
                return nil
            }
        }
    }
    
    private func createFile(at url: URL, data: Data) -> URL? {
        do {
            try data.write(to: url)
            return url
        } catch {
            print("❌ Failed to create temp file at \(url.path): \(error)")
            return nil
        }
    }

    /// Creates a ZIP archive strictly in-process via `NSFileCoordinator` (`.forUploading`)
    /// so archiving works cleanly under App Sandbox without spawning `/usr/bin/zip`.
    func createZip(from urls: [URL], suggestedName: String? = nil) async -> URL? {
        guard !urls.isEmpty else { return nil }
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let uuid = UUID().uuidString
        let rawArchiveName: String
        if let suggestedName, !suggestedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let clean = ShelfPolicy.sanitizeFilename(suggestedName, fallback: "Archive")
            rawArchiveName = clean.lowercased().hasSuffix(".zip") ? clean : "\(clean).zip"
        } else {
            rawArchiveName = ShelfPolicy.archiveFilename(itemCount: urls.count, primaryName: urls.first?.lastPathComponent)
        }

        return await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let workingDir = tempDir.appendingPathComponent("zip_\(uuid)", isDirectory: true)
            do {
                try fileManager.createDirectory(at: workingDir, withIntermediateDirectories: true)
            } catch {
                print("❌ Failed to create zip working directory: \(error)")
                return nil
            }

            let archiveURL = workingDir.appendingPathComponent(rawArchiveName)
            let startedFlags = urls.map { $0.startAccessingSecurityScopedResource() }
            defer {
                for (url, started) in zip(urls, startedFlags) where started {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            func coordinateArchive(of sourceURL: URL) -> Bool {
                var coordError: NSError?
                var copySucceeded = false
                let coordinator = NSFileCoordinator()
                coordinator.coordinate(readingItemAt: sourceURL, options: [.forUploading], error: &coordError) { zippedURL in
                    do {
                        if fileManager.fileExists(atPath: archiveURL.path) {
                            try fileManager.removeItem(at: archiveURL)
                        }
                        try fileManager.copyItem(at: zippedURL, to: archiveURL)
                        copySucceeded = true
                    } catch {
                        print("❌ Failed to stage coordinated archive: \(error)")
                    }
                }
                if let coordError {
                    print("❌ Archive coordination error: \(coordError.localizedDescription)")
                }
                return copySucceeded && coordError == nil
            }

            if urls.count == 1, let singleURL = urls.first {
                return coordinateArchive(of: singleURL) ? archiveURL : nil
            }

            let stagingDir = tempDir.appendingPathComponent("zip_stage_\(uuid)", isDirectory: true)
            defer { try? fileManager.removeItem(at: stagingDir) }
            do {
                try fileManager.createDirectory(at: stagingDir, withIntermediateDirectories: true)
            } catch {
                print("❌ Failed to create zip staging directory: \(error)")
                return nil
            }

            var copiedCount = 0
            for src in urls {
                let safeComponent = ShelfPolicy.sanitizeFilename(src.lastPathComponent, fallback: UUID().uuidString)
                var dest = stagingDir.appendingPathComponent(safeComponent)
                if fileManager.fileExists(atPath: dest.path) {
                    dest = stagingDir.appendingPathComponent("\(UUID().uuidString)_\(safeComponent)")
                }
                do {
                    try fileManager.copyItem(at: src, to: dest)
                    copiedCount += 1
                } catch {
                    print("⚠️ Failed to copy \(src.path) to zip staging dir: \(error)")
                }
            }

            guard copiedCount > 0 else {
                try? fileManager.removeItem(at: workingDir)
                return nil
            }
            if coordinateArchive(of: stagingDir) {
                return archiveURL
            }
            try? fileManager.removeItem(at: workingDir)
            return nil
        }.value
    }
    
    // MARK: - Content Creation Helpers
    
    
    private func createWeblocContent(for url: URL) -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>URL</key>
            <string>\(url.absoluteString)</string>
        </dict>
        </plist>
        """
    }
}
