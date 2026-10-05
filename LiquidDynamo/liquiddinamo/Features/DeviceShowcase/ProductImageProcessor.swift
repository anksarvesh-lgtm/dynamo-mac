//
//  ProductImageProcessor.swift
//  boringNotch
//
//  Created for Boring Notch
//

import AppKit
import CoreGraphics
import CoreImage
import Foundation
import Vision

// MARK: - Processed Product Image Result

public struct ProcessedProductImage {
    public let image: NSImage
    public let pngData: Data
    public let width: Int
    public let height: Int
    public let sourceURL: String?

    public init(image: NSImage, pngData: Data, width: Int = 1024, height: Int = 1024, sourceURL: String? = nil) {
        self.image = image
        self.pngData = pngData
        self.width = width
        self.height = height
        self.sourceURL = sourceURL
    }
}

// MARK: - Product Image Processor

public enum ProductImageProcessorError: LocalizedError {
    case invalidSourceImage
    case visionRequestFailed(String)
    case maskGenerationFailed
    case bitmapContextFailed
    case pngEncodingFailed

    public var errorDescription: String? {
        switch self {
        case .invalidSourceImage:
            return "Unable to decode input image into a valid CGImage."
        case .visionRequestFailed(let msg):
            return "Vision foreground segmentation failed: \(msg)"
        case .maskGenerationFailed:
            return "Unable to generate masked instance pixel buffer from Vision observation."
        case .bitmapContextFailed:
            return "Failed to allocate CoreGraphics bitmap rendering context."
        case .pngEncodingFailed:
            return "Failed to encode transparent image into PNG format."
        }
    }
}

public final class ProductImageProcessor {
    public static let shared = ProductImageProcessor()

    public init() {}

    /// Removes background using Vision `VNGenerateForegroundInstanceMaskRequest`,
    /// crops tightly to the isolated subject, pads symmetrically to 1:1 square, and
    /// exports a high-resolution 1024px transparent PNG.
    public func isolateProductSubject(
        from inputImage: NSImage,
        sourceURL: String? = nil,
        targetSize: CGFloat = 1024,
        padding: CGFloat = 72
    ) async throws -> ProcessedProductImage {
        guard let tiff = inputImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let cgImage = bitmap.cgImage else {
            throw ProductImageProcessorError.invalidSourceImage
        }

        return try await Task.detached(priority: .userInitiated) {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            let request = VNGenerateForegroundInstanceMaskRequest()

            do {
                try handler.perform([request])
            } catch {
                throw ProductImageProcessorError.visionRequestFailed(error.localizedDescription)
            }

            guard let result = request.results?.first else {
                throw ProductImageProcessorError.maskGenerationFailed
            }

            let pixelBuffer: CVPixelBuffer
            do {
                pixelBuffer = try result.generateMaskedImage(
                    ofInstances: result.allInstances,
                    from: handler,
                    croppedToInstancesExtent: false
                )
            } catch {
                throw ProductImageProcessorError.maskGenerationFailed
            }

            let ciContext = CIContext(options: nil)
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            guard let maskedCGImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
                throw ProductImageProcessorError.bitmapContextFailed
            }

            // 1. Scan for non-transparent pixel bounding box
            let width = maskedCGImage.width
            let height = maskedCGImage.height
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let scanContext = CGContext(
                    data: nil,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                throw ProductImageProcessorError.bitmapContextFailed
            }

            scanContext.draw(maskedCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let pixelData = scanContext.data else {
                throw ProductImageProcessorError.bitmapContextFailed
            }

            let ptr = pixelData.bindMemory(to: UInt8.self, capacity: width * height * 4)
            var minX = width
            var minY = height
            var maxX = 0
            var maxY = 0

            for y in 0..<height {
                for x in 0..<width {
                    let offset = (y * width + x) * 4
                    let alpha = ptr[offset + 3]
                    if alpha > 15 {
                        if x < minX { minX = x }
                        if x > maxX { maxX = x }
                        if y < minY { minY = y }
                        if y > maxY { maxY = y }
                    }
                }
            }

            // 2. Crop to subject bounding box
            let cropRect: CGRect
            if maxX >= minX && maxY >= minY {
                cropRect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
            } else {
                cropRect = CGRect(x: 0, y: 0, width: width, height: height)
            }

            guard let croppedCGImage = maskedCGImage.cropping(to: cropRect) else {
                throw ProductImageProcessorError.bitmapContextFailed
            }

            // 3. Composite onto 1024x1024 canvas with symmetric padding
            let maxSubjectDimension = targetSize - (padding * 2)
            let cropW = CGFloat(croppedCGImage.width)
            let cropH = CGFloat(croppedCGImage.height)
            let scale = min(maxSubjectDimension / max(cropW, 1), maxSubjectDimension / max(cropH, 1))

            let fittedW = cropW * scale
            let fittedH = cropH * scale
            let originX = (targetSize - fittedW) / 2.0
            let originY = (targetSize - fittedH) / 2.0

            guard let targetContext = CGContext(
                data: nil,
                width: Int(targetSize),
                height: Int(targetSize),
                bitsPerComponent: 8,
                bytesPerRow: Int(targetSize) * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                throw ProductImageProcessorError.bitmapContextFailed
            }

            targetContext.clear(CGRect(x: 0, y: 0, width: targetSize, height: targetSize))
            targetContext.draw(croppedCGImage, in: CGRect(x: originX, y: originY, width: fittedW, height: fittedH))

            guard let finalCGImage = targetContext.makeImage() else {
                throw ProductImageProcessorError.bitmapContextFailed
            }

            let finalRep = NSBitmapImageRep(cgImage: finalCGImage)
            guard let pngData = finalRep.representation(using: .png, properties: [:]) else {
                throw ProductImageProcessorError.pngEncodingFailed
            }

            let finalNSImage = NSImage(cgImage: finalCGImage, size: NSSize(width: targetSize, height: targetSize))
            return ProcessedProductImage(
                image: finalNSImage,
                pngData: pngData,
                width: Int(targetSize),
                height: Int(targetSize),
                sourceURL: sourceURL
            )
        }.value
    }

    /// Creates a transparent 1024x1024 bundled 3D asset image completely offline with zero web dependencies.
    public func createFromSymbol(icon: Premium3DIcon, targetSize: CGFloat = 1024) -> ProcessedProductImage? {
        let canvas = NSImage(size: NSSize(width: targetSize, height: targetSize))
        canvas.lockFocus()

        let config = NSImage.SymbolConfiguration(pointSize: targetSize * 0.65, weight: .bold)
        if let symbol = NSImage(systemSymbolName: icon.baseSymbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            let x = (targetSize - symbol.size.width) / 2.0
            let y = (targetSize - symbol.size.height) / 2.0
            symbol.draw(in: NSRect(x: x, y: y, width: symbol.size.width, height: symbol.size.height))
        }

        canvas.unlockFocus()

        guard let tiff = canvas.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            return nil
        }

        return ProcessedProductImage(
            image: canvas,
            pngData: pngData,
            width: Int(targetSize),
            height: Int(targetSize),
            sourceURL: "bundled://\(icon.rawValue)"
        )
    }
}
