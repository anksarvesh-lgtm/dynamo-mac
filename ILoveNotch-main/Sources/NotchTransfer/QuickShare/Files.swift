// SPDX-License-Identifier: MIT
import CoreServices
import Foundation
import UniformTypeIdentifiers

/// Names that are safe to save a received file under.
enum FileNames {
    /// Room for " 99" and more before the file system's 255-byte limit.
    static let maxBytes = 200

    /// No folders ("/", "\", and ":", which Finder shows as "/"), no control characters or ones that
    /// flip the reading direction (which can dress "fdp.app" up as "ppa.pdf"), not hidden, never
    /// empty, and short enough, keeping the extension.
    static func clean(_ name: String, replacing unsafe: String = "/\\:") -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in name.unicodeScalars {
            if unsafe.unicodeScalars.contains(scalar) {
                scalars.append("_")
            } else if scalar.properties.generalCategory != .control, !directionMarks.contains(scalar) {
                scalars.append(scalar)
            }
        }
        var clean = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        clean = String(clean.drop { $0 == "." || $0.isWhitespace })
        while clean.last == "." || clean.last?.isWhitespace == true { clean.removeLast() }
        guard !clean.isEmpty else { return "Untitled" }
        guard clean.utf8.count > maxBytes else { return clean }
        let name = clean as NSString
        let suffix = name.pathExtension.isEmpty || name.pathExtension.utf8.count > 16 ? "" : "." + name.pathExtension
        let base = suffix.isEmpty ? clean : name.deletingPathExtension
        return base.truncated(toUTF8Bytes: maxBytes - suffix.utf8.count) + suffix
    }

    /// A name for sending to Android: also without the characters its file systems and share
    /// sheet trip over.
    static func forAndroid(_ name: String) -> String { clean(name, replacing: "/\\:?%*|\"<>=") }

    /// "photo.jpg", then "photo 2.jpg", "photo 3.jpg", as Finder numbers copies.
    static func numbered(_ name: String, _ number: Int) -> String {
        guard number > 1 else { return name }
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? "\(name) \(number)" : "\((name as NSString).deletingPathExtension) \(number).\(ext)"
    }

    private static let directionMarks: Set<Unicode.Scalar> = [
        "\u{200E}", "\u{200F}", "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}", "\u{2066}", "\u{2067}",
        "\u{2068}", "\u{2069}",
    ]
}

extension String {
    /// As many whole characters as fit in `limit` bytes of UTF-8.
    func truncated(toUTF8Bytes limit: Int) -> String {
        var result = ""
        var count = 0
        for character in self {
            count += character.utf8.count
            guard count <= limit else { break }
            result.append(character)
        }
        return result
    }
}

/// A file on its way in, written as its chunks arrive to a temporary file on the same volume as
/// the folder it's going to. It takes its name there only once every byte it announced has come.
final class IncomingFile {
    let offer: FileOffer
    private let url: URL
    private let handle: FileHandle
    private(set) var written: Int64 = 0

    init(_ offer: FileOffer, in temporary: URL) throws {
        self.offer = offer
        url = temporary.appending(path: UUID().uuidString)
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw QuickShareError.files("Couldn't write to the folder for received files.")
        }
        handle = try FileHandle(forWritingTo: url)
    }

    deinit { try? handle.close() }

    /// Takes the next chunk, holding it to what the phone announced: in order, never past the
    /// size, and all of it by the last chunk.
    func write(_ chunk: PayloadFrame) throws {
        guard chunk.offset == written, Int64(chunk.body.count) <= offer.size - written else {
            throw QuickShareError.malformed
        }
        if !chunk.body.isEmpty {
            do {
                try handle.write(contentsOf: chunk.body)
            } catch {
                throw QuickShareError.files(error.localizedDescription)
            }
            written += Int64(chunk.body.count)
        }
        if chunk.isLast, written != offer.size { throw QuickShareError.malformed }
    }

    /// Moves the finished file into `folder` under a clean name, numbered if the name is taken,
    /// and marks it as downloaded, so macOS checks an app or script in it before it runs, as it
    /// does files from AirDrop.
    func save(in folder: URL) throws -> URL {
        try? handle.close()
        let name = FileNames.clean(offer.name)
        for number in 1...10_000 {
            var destination = folder.appending(path: FileNames.numbered(name, number))
            do {
                try FileManager.default.moveItem(at: url, to: destination)
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            } catch {
                throw QuickShareError.files(error.localizedDescription)
            }
            var values = URLResourceValues()
            values.quarantineProperties = [
                kLSQuarantineTypeKey as String: kLSQuarantineTypeOtherDownload as String,
                kLSQuarantineAgentNameKey as String: "ILoveNotch",
            ]
            try? destination.setResourceValues(values)
            return destination
        }
        throw QuickShareError.files("Couldn't find a free name for \(name).")
    }
}

/// A file on its way out, opened when its first chunk is read.
final class OutgoingFile {
    let url: URL
    let offer: FileOffer
    private(set) var sent: Int64 = 0
    private var handle: FileHandle?

    init(_ url: URL) throws {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentTypeKey])
        guard values?.isRegularFile == true, let size = values?.fileSize else {
            throw QuickShareError.files("\(url.lastPathComponent) can't be sent: only files can.")
        }
        self.url = url
        offer = FileOffer(
            name: FileNames.forAndroid(url.lastPathComponent), size: Int64(size),
            mimeType: values?.contentType?.preferredMIMEType ?? "application/octet-stream",
            payloadID: .random(in: .min ... .max))
    }

    deinit { try? handle?.close() }

    /// The next chunk, or nothing at the end, which must be where the file's size said.
    func read(upTo count: Int) throws -> Data {
        let chunk: Data
        do {
            if handle == nil { handle = try FileHandle(forReadingFrom: url) }
            chunk = try handle?.read(upToCount: count) ?? Data()
        } catch {
            throw QuickShareError.files("Couldn't read \(url.lastPathComponent).")
        }
        guard Int64(chunk.count) <= offer.size - sent, !chunk.isEmpty || sent == offer.size else {
            throw QuickShareError.files("\(url.lastPathComponent) changed while it was being sent.")
        }
        sent += Int64(chunk.count)
        if chunk.isEmpty { try? handle?.close() }
        return chunk
    }
}
