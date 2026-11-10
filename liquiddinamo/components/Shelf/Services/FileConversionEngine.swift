//
//  FileConversionEngine.swift
//  LiquidDynamo
//
//  Hardware-accelerated file format conversion and multi-page PDF generation engine.
//  Adopted from isleta's high-performance platform constraints.
//

import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum TargetFormat: String, CaseIterable, Identifiable, Sendable {
    case pdf = "PDF"
    case png = "PNG"
    case jpeg = "JPEG"
    case heic = "HEIC"
    case audioM4A = "M4A"

    public var id: String { rawValue }

    public var fileExtension: String {
        switch self {
        case .pdf: return "pdf"
        case .png: return "png"
        case .jpeg: return "jpg"
        case .heic: return "heic"
        case .audioM4A: return "m4a"
        }
    }

    public var utTypeIdentifier: String {
        switch self {
        case .pdf: return "com.adobe.pdf"
        case .png: return "public.png"
        case .jpeg: return "public.jpeg"
        case .heic: return "public.heic"
        case .audioM4A: return "com.apple.m4a-audio"
        }
    }
}

public final class FileConversionEngine {
    public static let shared = FileConversionEngine()

    private init() {}

    /// Batch converts a list of URLs to the target format.
    /// Returns the array of generated file URLs.
    public func convert(urls: [URL], to target: TargetFormat, outputDirectory: URL? = nil) async throws -> [URL] {
        guard !urls.isEmpty else { return [] }

        let destinationDir = outputDirectory ?? urls[0].deletingLastPathComponent()

        switch target {
        case .pdf:
            // Check if all are images -> combine into a single multi-page PDF
            let imageExtensions = ["png", "jpg", "jpeg", "heic", "webp", "tiff", "gif", "bmp"]
            let allImages = urls.allSatisfy { imageExtensions.contains($0.pathExtension.lowercased()) }
            if allImages && urls.count > 1 {
                let baseName = "Combined Document"
                let outputURL = try uniqueURL(in: destinationDir, base: baseName, ext: "pdf")
                try Self.imagesToPDF(urls, to: outputURL)
                return [outputURL]
            } else {
                // Convert each file individually to PDF
                var results: [URL] = []
                for url in urls {
                    let ext = url.pathExtension.lowercased()
                    if imageExtensions.contains(ext) {
                        let out = try uniqueURL(in: destinationDir, base: url.deletingPathExtension().lastPathComponent, ext: "pdf")
                        try Self.imagesToPDF([url], to: out)
                        results.append(out)
                    } else if ["docx", "rtf", "rtfd", "txt", "html"].contains(ext) {
                        let out = try uniqueURL(in: destinationDir, base: url.deletingPathExtension().lastPathComponent, ext: "pdf")
                        try Self.textDocumentToPDF(url, to: out)
                        results.append(out)
                    }
                }
                return results
            }

        case .png, .jpeg, .heic:
            var results: [URL] = []
            for url in urls {
                let out = try uniqueURL(in: destinationDir, base: url.deletingPathExtension().lastPathComponent, ext: target.fileExtension)
                try Self.encodeImage(url, to: out, typeIdentifier: target.utTypeIdentifier)
                results.append(out)
            }
            return results

        case .audioM4A:
            var results: [URL] = []
            for url in urls {
                let out = try uniqueURL(in: destinationDir, base: url.deletingPathExtension().lastPathComponent, ext: "m4a")
                try await Self.extractAudioToM4A(url, to: out)
                results.append(out)
            }
            return results
        }
    }

    // MARK: - Hardware Image Encoding

    private static func encodeImage(_ input: URL, to outputURL: URL, typeIdentifier: String) throws {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(domain: "FileConversionEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not read source image"])
        }

        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, typeIdentifier as CFString, 1, nil) else {
            throw NSError(domain: "FileConversionEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not initialize image destination"])
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.9
        ]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "FileConversionEngine", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not write converted image"])
        }
    }

    // MARK: - Multi-Page PDF Generation via CGImageDestination

    /// Combines multiple images into a multi-page PDF in <500 ms using CGImageDestination.
    private static func imagesToPDF(_ inputs: [URL], to outputURL: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL, "com.adobe.pdf" as CFString, inputs.count, nil
        ) else {
            throw NSError(domain: "FileConversionEngine", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not create PDF destination"])
        }

        var addedCount = 0
        for input in inputs {
            guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
                  CGImageSourceGetCount(source) > 0,
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
            CGImageDestinationAddImage(destination, image, nil)
            addedCount += 1
        }

        guard addedCount > 0 else {
            throw NSError(domain: "FileConversionEngine", code: 5, userInfo: [NSLocalizedDescriptionKey: "No readable images were found"])
        }

        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "FileConversionEngine", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize PDF document"])
        }
    }

    // MARK: - Text / Document to PDF

    private static func textDocumentToPDF(_ input: URL, to outputURL: URL) throws {
        let attrString = try NSAttributedString(url: input, options: [:], documentAttributes: nil)

        let printInfo = NSPrintInfo.shared
        printInfo.paperSize = NSSize(width: 595.2, height: 841.8) // A4
        printInfo.topMargin = 36.0
        printInfo.bottomMargin = 36.0
        printInfo.leftMargin = 36.0
        printInfo.rightMargin = 36.0

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: printInfo.paperSize.width - 72, height: printInfo.paperSize.height - 72))
        textView.textStorage?.setAttributedString(attrString)

        let printOp = NSPrintOperation(view: textView, printInfo: printInfo)
        printOp.showsPrintPanel = false
        printOp.showsProgressPanel = false

        let pdfData = NSMutableData()
        let consumer = CGDataConsumer(data: pdfData as CFMutableData)!
        var mediaBox = CGRect(origin: .zero, size: printInfo.paperSize)
        guard let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw NSError(domain: "FileConversionEngine", code: 7, userInfo: [NSLocalizedDescriptionKey: "Could not create PDF context"])
        }

        let printContext = NSGraphicsContext(cgContext: pdfContext, flipped: false)
        let oldContext = NSGraphicsContext.current
        NSGraphicsContext.current = printContext

        pdfContext.beginPage(mediaBox: &mediaBox)
        textView.draw(textView.bounds)
        pdfContext.endPage()
        pdfContext.closePDF()

        NSGraphicsContext.current = oldContext
        try pdfData.write(to: outputURL, options: .atomic)
    }

    // MARK: - Audio Extraction via AVAssetExportSession

    private static func extractAudioToM4A(_ input: URL, to outputURL: URL) async throws {
        let asset = AVAsset(url: input)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(domain: "FileConversionEngine", code: 8, userInfo: [NSLocalizedDescriptionKey: "Export preset unavailable"])
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        await exportSession.export()

        if let error = exportSession.error {
            throw error
        }
    }

    // MARK: - Unique File Naming

    private func uniqueURL(in directory: URL, base: String, ext: String) throws -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent(base).appendingPathExtension(ext)
        var suffix = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(base) \(suffix)")
                .appendingPathExtension(ext)
            suffix += 1
            if suffix > 1000 { break }
        }
        return candidate
    }
}

