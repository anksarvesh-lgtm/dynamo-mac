//
//  Image2Color.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import SwiftUI
import AppKit
import Cocoa
import Foundation
import CoreImage
import CoreGraphics
import CoreImage.CIFilterBuiltins

extension NSImage {

    /// Safely extracts a non-empty `CGImage` from this `NSImage`, verifying valid raster dimensions.
    public var safeCGImage: CGImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        var proposedRect = CGRect(origin: .zero, size: size)
        guard let cg = cgImage(forProposedRect: &proposedRect, context: nil, hints: nil),
              cg.width > 0, cg.height > 0 else {
            return nil
        }
        return cg
    }

    /// Safely provides an `NSBitmapImageRep` with non-zero dimensions without triggering
    /// `CGImageDestinationFinalize failed for output type 'public.tiff'`.
    public var safeBitmapRepresentation: NSBitmapImageRep? {
        // 1. Check existing representations for a valid raster bitmap
        for rep in representations {
            if let bitmap = rep as? NSBitmapImageRep,
               bitmap.pixelsWide > 0,
               bitmap.pixelsHigh > 0 {
                return bitmap
            }
        }

        // 2. If no valid NSBitmapImageRep exists, render from verified CGImage
        if let cg = safeCGImage {
            return NSBitmapImageRep(cgImage: cg)
        }

        // 3. Fallback: try drawing into a dedicated bitmap context
        guard size.width > 0, size.height > 0 else { return nil }
        let width = max(1, Int(ceil(size.width)))
        let height = max(1, Int(ceil(size.height)))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current = context
        draw(in: NSRect(x: 0, y: 0, width: width, height: height),
             from: .zero,
             operation: .copy,
             fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        return (rep.pixelsWide > 0 && rep.pixelsHigh > 0) ? rep : nil
    }

    /// Safely serializes to TIFF data without triggering CoreGraphics empty destination errors.
    public var safeTIFFRepresentation: Data? {
        guard let rep = safeBitmapRepresentation else { return nil }
        return rep.tiffRepresentation
    }

    /// Safely serializes to PNG data without triggering CoreGraphics empty destination errors.
    public func safePNGRepresentation() -> Data? {
        guard let rep = safeBitmapRepresentation else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Safely serializes to JPEG data without triggering CoreGraphics empty destination errors.
    public func safeJPEGRepresentation(compressionFactor: Double = 0.85) -> Data? {
        guard let rep = safeBitmapRepresentation else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: compressionFactor])
    }

    /// Generates a thumbnail Data using CGImageSource or fallback to safe PNG.
    public func safeThumbnailData(maxPixelSize: CGFloat) -> Data? {
        guard let sourceData = safePNGRepresentation() else { return nil }
        guard let imageSource = CGImageSourceCreateWithData(sourceData as CFData, nil) else {
            return sourceData
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return sourceData
        }
        let rep = NSBitmapImageRep(cgImage: thumbnail)
        return rep.representation(using: .png, properties: [:]) ?? sourceData
    }

    
    func averageColor(completion: @escaping (NSColor?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            let width = cgImage.width
            let height = cgImage.height
            let totalPixels = width * height
            
            guard let context = CGContext(data: nil,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            
            guard let data = context.data else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            let pointer = data.bindMemory(to: UInt32.self, capacity: totalPixels)
            
            var totalRed: UInt64 = 0
            var totalGreen: UInt64 = 0
            var totalBlue: UInt64 = 0
            
            for i in 0..<totalPixels {
                let color = pointer[i]
                totalRed += UInt64(color & 0xFF)
                totalGreen += UInt64((color >> 8) & 0xFF)
                totalBlue += UInt64((color >> 16) & 0xFF)
            }
            
            let averageRed = CGFloat(totalRed) / CGFloat(totalPixels) / 255.0
            let averageGreen = CGFloat(totalGreen) / CGFloat(totalPixels) / 255.0
            let averageBlue = CGFloat(totalBlue) / CGFloat(totalPixels) / 255.0
            
            let minBrightness: CGFloat = 0.5
            let isNearBlack = averageRed < 0.03 && averageGreen < 0.03 && averageBlue < 0.03
            
            var finalColor: NSColor
            
            if isNearBlack {
                // If it's near black, just return a gray color with the minimum brightness
                finalColor = NSColor(white: minBrightness, alpha: 1.0)
            } else {
                var color = NSColor(red: averageRed, green: averageGreen, blue: averageBlue, alpha: 1.0)
                
                var hue: CGFloat = 0
                var saturation: CGFloat = 0
                var brightness: CGFloat = 0
                var alpha: CGFloat = 0
                
                color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
                
                if brightness < minBrightness {
                    // Increase brightness while maintaining hue and reducing saturation
                    let saturationScale = brightness / minBrightness
                    color = NSColor(hue: hue,
                                    saturation: saturation * saturationScale,
                                    brightness: minBrightness,
                                    alpha: alpha)
                }
                
                finalColor = color
            }
            
            DispatchQueue.main.async {
                completion(finalColor)
            }
        }
        
    }
    
    func getBrightness() -> CGFloat {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return 0
        }
        
        let inputImage = CIImage(cgImage: cgImage)
        
        let filter = CIFilter.areaAverage()
        filter.inputImage = inputImage
        filter.extent = inputImage.extent
        
        guard let outputImage = filter.outputImage else {
            return 0
        }
        
        let context = CIContext(options: nil)
        
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(outputImage,
                       toBitmap: &bitmap,
                       rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())
        
        let brightness = (0.2126 * CGFloat(bitmap[0]) + 0.7152 * CGFloat(bitmap[1]) + 0.0722 * CGFloat(bitmap[2])) / 255.0
        
        return brightness
    }
}

extension Color {
    func ensureMinimumBrightness(factor: CGFloat) -> Color {
        guard factor >= 0 && factor <= 1 else {
            return self // Return original color if factor is out of bounds
        }
        
        let nsColor = NSColor(self)
        
        // Convert to RGB color space
        guard let rgbColor = nsColor.usingColorSpace(.sRGB) else {
            return self // Return original color if conversion fails
        }
        
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        rgbColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        // Calculate perceived brightness using the formula: (0.299*R + 0.587*G + 0.114*B)
        let perceivedBrightness = (0.2126 * red + 0.7152 * green + 0.0722 * blue)
        
        let scale = factor / perceivedBrightness
        red = min(red * scale, 1.0)
        green = min(green * scale, 1.0)
        blue = min(blue * scale, 1.0)
        
        return Color(red: Double(red), green: Double(green), blue: Double(blue), opacity: Double(alpha))
    }
}
